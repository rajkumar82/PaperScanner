import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/detected_mark.dart';
import '../models/page_result.dart';
import 'annotator.dart';
import 'mark_detector.dart';
import 'ocr_service.dart';

/// Runs the full per-page pipeline: OCR the whole page to find every
/// digit (any colour, any location), then check each one against the page
/// image directly to see whether it's actually circled in red, draw the
/// confirmed marks back onto the page, and fill in a [PageResult].
class PageProcessor {
  PageProcessor(this._ocr);

  final OcrService _ocr;

  Future<void> process(PageResult page, String workDir) async {
    final marks = <DetectedMark>[];
    Uint8List? displayBytes;
    String debugLabel;

    try {
      final bytes = await page.rawImageFile.readAsBytes();

      // Whole-page OCR first (finds every digit regardless of colour) -
      // a platform-channel call, has to run on the main isolate.
      final candidates = await _ocr.recognizeAllDigits(page.rawImageFile.path);
      final hits = candidates
          .map((c) => OcrHit(
                value: c.value,
                left: c.rect.left,
                top: c.rect.top,
                right: c.rect.right,
                bottom: c.rect.bottom,
              ))
          .toList();

      // Then, per digit, check whether it's actually sitting inside a red
      // ring - pure image analysis, safe to run in the background.
      final result = await verifyMarks(bytes, hits);
      displayBytes = result.displayImageJpeg;

      for (final m in result.marks) {
        marks.add(DetectedMark(
          value: m.value,
          x: m.displayX,
          y: m.displayY,
          width: m.displayWidth,
          height: m.displayHeight,
        ));
      }

      // Surfaced on the page itself (debug builds only) so a processing
      // outcome is visible straight from the exported PDF, without needing
      // device log access - this pipeline has needed a lot of real-device
      // debugging and `debugPrint` alone hasn't been enough for that.
      debugLabel = 'det: ${result.stats}';
    } catch (e, st) {
      debugPrint('Page ${page.index} processing failed: $e\n$st');
      debugLabel = 'ERROR: $e';
    }

    try {
      displayBytes ??= await _fallbackDisplayImage(page.rawImageFile);

      final displayFile = File(p.join(workDir, 'page_${page.index}_display.jpg'));
      await displayFile.writeAsBytes(displayBytes, flush: true);

      final annotatedBytes = await annotateImage(displayBytes, marks, debugLabel: debugLabel);
      final annotatedFile = File(p.join(workDir, 'page_${page.index}_annotated.jpg'));
      await annotatedFile.writeAsBytes(annotatedBytes, flush: true);

      page.marks = marks;
      page.displayImageFile = displayFile;
      page.annotatedImageFile = annotatedFile;
    } catch (e, st) {
      // If even building the fallback/annotated image fails, the page is
      // left with no display/annotated file and contributes 0 - the
      // session shouldn't crash over one bad photo.
      debugPrint('Page ${page.index} fallback rendering failed: $e\n$st');
    } finally {
      page.processing = false;
    }
  }

  /// Used only when [verifyMarks] throws before producing its own resized
  /// copy - decodes and resizes the raw (already cropped) page directly so
  /// there's still something to show, with the error banner on it.
  Future<Uint8List> _fallbackDisplayImage(File rawImageFile) async {
    final bytes = await rawImageFile.readAsBytes();
    return compute(_resizeForDisplay, bytes);
  }
}

Uint8List _resizeForDisplay(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return bytes;
  image = img.bakeOrientation(image);
  final resized = img.copyResize(
    image,
    width: image.width > 1600 ? 1600 : image.width,
    maintainAspect: true,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
}
