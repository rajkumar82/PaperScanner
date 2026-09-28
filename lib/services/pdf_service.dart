import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/page_result.dart';

/// Compiles the captured pages into a PDF and hands it off through
/// Android's share sheet - the app doesn't manage any persistent storage
/// of its own for the exported file.
class PdfService {
  Future<void> shareAsPdf(List<PageResult> pages) async {
    final doc = pw.Document();

    for (final page in pages) {
      final bytes = await page.displayFile.readAsBytes();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final bytes = await doc.save();
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    await Printing.sharePdf(bytes: bytes, filename: 'paperscanner_$stamp.pdf');
  }
}
