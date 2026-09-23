import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A word-level piece of text ML Kit recognized that parses as a plausible
/// mark value - regardless of colour or location. Whether it's actually
/// circled in red is checked afterwards, against the page image directly
/// (see `mark_detector.dart`'s `verifyMarks`).
class OcrDigitCandidate {
  OcrDigitCandidate({required this.value, required this.rect});
  final int value;
  final Rect rect;
}

/// Runs on-device OCR once per page and sanitizes the result down to
/// plausible mark values with their locations.
///
/// Kept as a single long-lived instance for a scan session, since spinning
/// up a [TextRecognizer] per call is wasteful.
class OcrService {
  OcrService() : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  /// Runs OCR on the whole page at [imagePath] and returns every
  /// word-level piece of text that parses as a plausible mark (0-100),
  /// with its location - this deliberately includes printed numbers,
  /// question numbers, blue-pen working, anything numeric anywhere on the
  /// page. Colour/circle filtering happens as a separate step, once each
  /// candidate's actual location is known.
  Future<List<OcrDigitCandidate>> recognizeAllDigits(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final result = await _recognizer.processImage(inputImage);
      final candidates = <OcrDigitCandidate>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final value = _sanitize(element.text);
            if (value != null) {
              candidates.add(OcrDigitCandidate(value: value, rect: element.boundingBox));
            }
          }
        }
      }
      return candidates;
    } catch (e) {
      debugPrint('Whole-page OCR failed: $e');
      return const [];
    }
  }

  int? _sanitize(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final value = int.tryParse(digits);
    if (value == null) return null;
    if (value < 0 || value > 100) return null;
    return value;
  }

  Future<void> close() => _recognizer.close();
}
