import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/page_result.dart';

/// Resizes a captured page to display/export resolution and fills in a
/// [PageResult]. Runs off the UI thread via `compute()` so the capture loop
/// keeps watching for the next page turn while this finishes.
class PageProcessor {
  Future<void> process(PageResult page, String workDir) async {
    try {
      final bytes = await page.rawImageFile.readAsBytes();
      final displayBytes = await compute(_resizeForDisplay, bytes);

      final displayFile = File(p.join(workDir, 'page_${page.index}_display.jpg'));
      await displayFile.writeAsBytes(displayBytes, flush: true);

      page.displayImageFile = displayFile;
    } catch (e, st) {
      // If resizing fails, the page falls back to its raw image rather
      // than crashing the session over one bad photo.
      debugPrint('Page ${page.index} processing failed: $e\n$st');
    } finally {
      page.processing = false;
    }
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
