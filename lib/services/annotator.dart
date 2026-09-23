import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/detected_mark.dart';

class _AnnotateInput {
  _AnnotateInput(this.displayImageJpeg, this.marks, this.debugLabel);
  final Uint8List displayImageJpeg;
  final List<DetectedMark> marks;
  final String? debugLabel;
}

/// Draws each recognized mark value on top of its red circle, on a copy of
/// the display-resolution page image. Pure image manipulation (no platform
/// channels involved) so it's safe to run on a background isolate.
///
/// [debugLabel], when set, is drawn as a small banner regardless of
/// whether any marks were found - in debug builds only. This is what lets
/// a processing outcome (found N candidates, M recognized, or an
/// exception) show up directly in the exported PDF while the detection
/// pipeline is still being tuned against real captures, without needing
/// device log access.
Future<Uint8List> annotateImage(
  Uint8List displayImageJpeg,
  List<DetectedMark> marks, {
  String? debugLabel,
}) {
  final label = kDebugMode ? debugLabel : null;
  if (marks.isEmpty && label == null) return Future.value(displayImageJpeg);
  return compute(_annotateIsolate, _AnnotateInput(displayImageJpeg, marks, label));
}

Uint8List _annotateIsolate(_AnnotateInput input) {
  final decoded = img.decodeImage(input.displayImageJpeg);
  if (decoded == null) return input.displayImageJpeg;
  var canvas = decoded;
  final imageWidth = canvas.width;

  for (final m in input.marks) {
    final text = m.value.toString();
    final boxWidth = 14 * text.length + 10;
    final maxX = math.max(0, imageWidth - boxWidth);
    final boxX = m.x.clamp(0, maxX);
    final boxY = math.max(0, m.y - 28);

    canvas = img.drawRect(
      canvas,
      x1: boxX,
      y1: boxY,
      x2: boxX + boxWidth,
      y2: boxY + 26,
      color: img.ColorRgba8(0, 0, 0, 170),
      radius: 4,
    );
    canvas = img.drawString(
      canvas,
      text,
      font: img.arial24,
      x: boxX + 5,
      y: boxY + 2,
      color: img.ColorRgb8(90, 230, 130),
    );
  }

  final label = input.debugLabel;
  if (label != null) {
    final truncated = label.length > 220 ? '${label.substring(0, 220)}...' : label;
    canvas = img.fillRect(
      canvas,
      x1: 0,
      y1: 0,
      x2: canvas.width,
      y2: 90,
      color: img.ColorRgba8(0, 0, 0, 190),
    );
    canvas = img.drawString(
      canvas,
      truncated,
      font: img.arial14,
      x: 6,
      y: 6,
      color: img.ColorRgb8(255, 220, 60),
      wrap: true,
    );
  }

  return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
}
