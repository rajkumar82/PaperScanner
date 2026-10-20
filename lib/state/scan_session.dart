import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/page_result.dart';
import '../services/pdf_service.dart';

/// Holds the pages of the scan in progress. Backed by a scratch folder in
/// temp storage that is wiped at the start of every new scan - nothing here
/// is meant to persist.
class ScanSession extends ChangeNotifier {
  final PdfService _pdf = PdfService();

  Directory? _sessionDir;
  final List<PageResult> _pages = [];
  int _fileCounter = 0;

  List<PageResult> get pages => List.unmodifiable(_pages);

  /// Clears any previous scan's files and starts a fresh one.
  Future<void> start() async {
    final tempRoot = await getTemporaryDirectory();
    final dir = Directory(p.join(tempRoot.path, 'paperscanner_session'));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    _sessionDir = dir;
    _pages.clear();
    _fileCounter = 0;
    notifyListeners();
  }

  /// A fresh, unique path inside the scratch folder.
  String newFilePath(String name) =>
      p.join(_sessionDir!.path, '${_fileCounter++}_$name');

  void addPage(File file) {
    _pages.add(PageResult(index: _pages.length, file: file));
    notifyListeners();
  }

  void removePage(int index) {
    _pages.removeAt(index);
    for (var i = 0; i < _pages.length; i++) {
      _pages[i] = PageResult(index: i, file: _pages[i].file);
    }
    notifyListeners();
  }

  Future<void> sharePdf() => _pdf.shareAsPdf(_pages);
}
