import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// One page of a [Scan]: the untouched camera photo plus the rotation/crop
/// the user chose, and the rendered result used for display and the PDF.
/// File names are relative to the scan's folder.
class ScanPage {
  ScanPage({
    required this.original,
    required this.rendered,
    required this.turns,
    required this.crop,
  });

  final String original;
  final String rendered;

  /// Clockwise quarter turns applied to the original.
  final int turns;

  /// Crop rectangle in the rotated photo, as 0..1 fractions.
  final Rect crop;

  Map<String, dynamic> toJson() => {
    'original': original,
    'rendered': rendered,
    'turns': turns,
    'crop': [crop.left, crop.top, crop.right, crop.bottom],
  };

  factory ScanPage.fromJson(Map<String, dynamic> j) {
    final c = (j['crop'] as List).map((v) => (v as num).toDouble()).toList();
    return ScanPage(
      original: j['original'] as String,
      rendered: j['rendered'] as String,
      turns: j['turns'] as int,
      crop: Rect.fromLTRB(c[0], c[1], c[2], c[3]),
    );
  }
}

/// A saved scan: a folder holding the original photos, the rendered pages
/// and a `scan.json` describing them, so it can be re-edited later.
class Scan extends ChangeNotifier {
  Scan({
    required this.id,
    required this.dir,
    required this.createdAt,
    List<ScanPage>? pages,
  }) : pages = pages ?? [];

  static const _jsonName = 'scan.json';

  final String id;
  final Directory dir;
  final DateTime createdAt;
  final List<ScanPage> pages;

  /// Creates a new, empty scan folder under [root].
  static Future<Scan> create(Directory root) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();
    final dir = Directory(p.join(root.path, id));
    await dir.create(recursive: true);
    return Scan(id: id, dir: dir, createdAt: now);
  }

  /// Reads a scan folder, or returns null if it has no valid `scan.json`.
  static Future<Scan?> fromDir(Directory dir) async {
    try {
      final f = File(p.join(dir.path, _jsonName));
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return Scan(
        id: j['id'] as String,
        dir: dir,
        createdAt: DateTime.parse(j['createdAt'] as String),
        pages: (j['pages'] as List)
            .map((e) => ScanPage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      debugPrint('Skipping unreadable scan ${dir.path}: $e');
      return null;
    }
  }

  File _file(String name) => File(p.join(dir.path, name));
  File originalOf(ScanPage page) => _file(page.original);
  File renderedOf(ScanPage page) => _file(page.rendered);
  List<File> get renderedFiles => pages.map(renderedOf).toList();

  /// e.g. "20 Oct 2026, 14:32".
  String get title {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String two(int n) => n.toString().padLeft(2, '0');
    final d = createdAt;
    return '${d.day} ${months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
  }

  String _stamp() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> save() async {
    final json = jsonEncode({
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'pages': pages.map((e) => e.toJson()).toList(),
    });
    // Write then rename so a crash mid-write can't corrupt the scan.
    final tmp = _file('$_jsonName.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(p.join(dir.path, _jsonName));
    notifyListeners();
  }

  /// Adds a new page: keeps a copy of the camera [photo] as its original.
  Future<void> addPage(File photo, int turns, Rect crop, Uint8List jpeg) async {
    final stamp = _stamp();
    final original = 'orig_$stamp.jpg';
    final rendered = 'page_$stamp.jpg';
    await photo.copy(p.join(dir.path, original));
    await _file(rendered).writeAsBytes(jpeg, flush: true);
    pages.add(
      ScanPage(
        original: original,
        rendered: rendered,
        turns: turns,
        crop: crop,
      ),
    );
    await save();
  }

  /// Replaces a page's rotation/crop and rendered image. The rendered file
  /// gets a fresh name so cached images refresh.
  Future<void> updatePage(
    int index,
    int turns,
    Rect crop,
    Uint8List jpeg,
  ) async {
    final old = pages[index];
    final rendered = 'page_${_stamp()}.jpg';
    await _file(rendered).writeAsBytes(jpeg, flush: true);
    pages[index] = ScanPage(
      original: old.original,
      rendered: rendered,
      turns: turns,
      crop: crop,
    );
    await save();
    await _deleteQuietly(old.rendered);
  }

  Future<void> removePage(int index) async {
    final old = pages.removeAt(index);
    await save();
    await _deleteQuietly(old.original);
    await _deleteQuietly(old.rendered);
  }

  Future<void> _deleteQuietly(String name) async {
    try {
      await _file(name).delete();
    } catch (_) {}
  }
}
