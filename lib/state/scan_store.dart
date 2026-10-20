import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/scan.dart';

/// The library of saved scans, newest first. Each scan lives in its own
/// folder under the app's private documents directory.
class ScanStore extends ChangeNotifier {
  final List<Scan> _scans = [];
  bool _loaded = false;

  List<Scan> get scans => List.unmodifiable(_scans);
  bool get loaded => _loaded;

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'scans'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    try {
      final root = await _root();
      final found = <Scan>[];
      await for (final entry in root.list()) {
        if (entry is! Directory) continue;
        final scan = await Scan.fromDir(entry);
        if (scan != null && scan.pages.isNotEmpty) found.add(scan);
      }
      found.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final s in _scans) {
        s.removeListener(notifyListeners);
      }
      _scans
        ..clear()
        ..addAll(found);
      for (final s in _scans) {
        s.addListener(notifyListeners);
      }
    } catch (e) {
      debugPrint('Could not load scans: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Creates a scan folder. It only appears in the list once [register]ed
  /// (after its first page is saved), so abandoned scans leave no trace.
  Future<Scan> create() async => Scan.create(await _root());

  void register(Scan scan) {
    if (_scans.contains(scan)) return;
    _scans.insert(0, scan);
    scan.addListener(notifyListeners);
    notifyListeners();
  }

  Future<void> delete(Scan scan) async {
    scan.removeListener(notifyListeners);
    _scans.remove(scan);
    notifyListeners();
    try {
      await scan.dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Could not delete ${scan.dir.path}: $e');
    }
  }
}
