import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:paperscanner/services/mark_detector.dart';

void main() {
  test('confirms a digit sitting inside a red ring, rejects one that is not', () async {
    // A synthetic "page": white background, a dark blob standing in for a
    // handwritten digit with a red ring drawn around it (like a teacher's
    // circled mark), a stray red tick mark elsewhere that doesn't enclose
    // a hole, and a "printed digit" with no red near it at all. In the
    // real pipeline, OCR would report all three digit-shaped locations
    // (it doesn't know or care about colour); [verifyMarks] simulates
    // that by taking the hit locations directly, and its job is to keep
    // only the one that's actually circled in red.
    var page = img.Image(width: 800, height: 600);
    page = img.fill(page, color: img.ColorRgb8(255, 255, 255));

    // The real, circled digit.
    page = img.fillRect(page, x1: 380, y1: 280, x2: 420, y2: 320, color: img.ColorRgb8(20, 20, 20));
    for (final radius in [51, 53, 55]) {
      page = img.drawCircle(page, x: 400, y: 300, radius: radius, color: img.ColorRgb8(200, 20, 20));
    }

    // A stray red tick mark near a second "digit" - not a ring, must be
    // rejected even though there's plenty of red right there.
    page = img.fillRect(page, x1: 90, y1: 90, x2: 130, y2: 130, color: img.ColorRgb8(20, 20, 20));
    page = img.drawLine(page, x1: 100, y1: 100, x2: 130, y2: 130, color: img.ColorRgb8(200, 20, 20), thickness: 4);
    page = img.drawLine(page, x1: 130, y1: 100, x2: 100, y2: 130, color: img.ColorRgb8(200, 20, 20), thickness: 4);

    // A third "digit" with no red ink anywhere near it - e.g. a printed
    // page number.
    page = img.fillRect(page, x1: 580, y1: 480, x2: 620, y2: 520, color: img.ColorRgb8(20, 20, 20));

    final bytes = Uint8List.fromList(img.encodeJpg(page, quality: 95));

    final hits = [
      OcrHit(value: 3, left: 380, top: 280, right: 420, bottom: 320), // circled - should survive
      OcrHit(value: 9, left: 90, top: 90, right: 130, bottom: 130), // tick mark, not a ring
      OcrHit(value: 7, left: 580, top: 480, right: 620, bottom: 520), // no red at all
    ];

    final result = await verifyMarks(bytes, hits);

    expect(result.marks.length, 1, reason: 'only the digit actually inside a red ring should survive');
    expect(result.marks.single.value, 3);
    expect(result.stats.ocrHits, 3);
  });
}
