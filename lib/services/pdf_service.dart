import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Compiles page images into a PDF and saves it to the device's Downloads
/// folder, optionally followed by Android's share sheet.
class PdfService {
  static const _channel = MethodChannel('paperscanner/downloads');

  Future<Uint8List> _build(List<File> pages) async {
    final doc = pw.Document();
    for (final page in pages) {
      final image = pw.MemoryImage(await page.readAsBytes());
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    return doc.save();
  }

  String _fileName() {
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    return 'paperscanner_$stamp.pdf';
  }

  Future<String> _saveBytes(Uint8List bytes, String name) async {
    final saved = await _channel.invokeMethod<String>('savePdf', {
      'name': name,
      'bytes': bytes,
    });
    return saved ?? name;
  }

  /// Saves into Downloads and returns the file name.
  Future<String> saveToDownloads(List<File> pages) async {
    return _saveBytes(await _build(pages), _fileName());
  }

  /// Saves into Downloads first (so the PDF is never lost if sharing is
  /// cancelled or fails), then opens the share sheet. Returns the saved file
  /// name, or null if the save step failed - sharing still goes ahead.
  Future<String?> saveAndShare(List<File> pages) async {
    final bytes = await _build(pages);
    final name = _fileName();
    String? saved;
    try {
      saved = await _saveBytes(bytes, name);
    } catch (e) {
      debugPrint('Could not save before sharing: $e');
    }
    await Printing.sharePdf(bytes: bytes, filename: name);
    return saved;
  }
}
