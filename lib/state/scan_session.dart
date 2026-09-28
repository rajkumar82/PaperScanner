import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/page_result.dart';
import '../services/page_processor.dart';
import '../services/pdf_service.dart';

/// Holds everything for the scan currently in progress (or just finished):
/// the captured/processed pages. Backed entirely by a scratch folder in
/// temp storage that gets wiped at the start of every new session - nothing
/// here is meant to persist.
class ScanSession extends ChangeNotifier {
  final PdfService _pdf = PdfService();
  final PageProcessor _processor = PageProcessor();

  Directory? _sessionDir;
  final List<PageResult> _pages = [];
  bool _active = false;

  List<PageResult> get pages => List.unmodifiable(_pages);
  bool get active => _active;
  bool get isProcessing => _pages.any((page) => page.processing);

  /// Clears any previous session's files and starts a fresh one. Returns
  /// the folder new captures should be written into.
  Future<String> start() async {
    final tempRoot = await getTemporaryDirectory();
    final dir = Directory(p.join(tempRoot.path, 'paperscanner_session'));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    _sessionDir = dir;
    _pages.clear();
    _active = true;
    notifyListeners();
    return dir.path;
  }

  String get sessionDirPath => _sessionDir!.path;

  void stop() {
    _active = false;
    notifyListeners();
  }

  /// Registers a freshly captured page and kicks off its (async, non
  /// blocking) resize pass.
  Future<void> addCapturedPage(File rawImage) async {
    final page = PageResult(index: _pages.length, rawImageFile: rawImage);
    _pages.add(page);
    notifyListeners();

    await _processor.process(page, sessionDirPath);
    notifyListeners();
  }

  Future<void> sharePdf() {
    return _pdf.shareAsPdf(_pages);
  }
}
