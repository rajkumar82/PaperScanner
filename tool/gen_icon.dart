// One-off generator for the launcher icon artwork: a document with a
// red-circled checkmark, echoing the app's actual "circle a mark on a
// page" feature. Produces:
//   assets/icon/foreground.png  - transparent background, for the
//                                 Android adaptive icon foreground layer
//   assets/icon/icon.png        - same art flattened over the app's green,
//                                 used as the plain/legacy icon
//
// Not part of the app itself - run once with `dart run tool/gen_icon.dart`
// whenever the icon design needs to change, then regenerate the launcher
// icons with `dart run flutter_launcher_icons`.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int kSize = 1024;
final _green = img.ColorRgb8(0x2E, 0x7D, 0x32);
final _white = img.ColorRgb8(0xFF, 0xFF, 0xFF);
final _red = img.ColorRgb8(0xD3, 0x2F, 0x2F);

void main() {
  Directory('assets/icon').createSync(recursive: true);

  final foreground = _art(transparentBg: true);
  File('assets/icon/foreground.png').writeAsBytesSync(img.encodePng(foreground));

  final flat = _art(transparentBg: false);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(flat));

  // ignore: avoid_print
  print('Wrote assets/icon/foreground.png and assets/icon/icon.png');
}

img.Image _art({required bool transparentBg}) {
  var canvas = img.Image(width: kSize, height: kSize, numChannels: 4);
  canvas = img.fill(
    canvas,
    color: transparentBg ? img.ColorRgba8(0, 0, 0, 0) : img.ColorRgba8(_green.r.toInt(), _green.g.toInt(), _green.b.toInt(), 255),
  );

  // The page.
  canvas = img.fillRect(
    canvas,
    x1: 280,
    y1: 230,
    x2: 744,
    y2: 794,
    color: _white,
    radius: 32,
  );

  // A bold red ring - the app's "circled mark". Filled disk punched out by
  // a smaller white disk, rather than stacked outlines, so the band comes
  // out smooth instead of banded.
  canvas = img.fillCircle(canvas, x: 610, y: 610, radius: 150, color: _red, antialias: true);
  canvas = img.fillCircle(canvas, x: 610, y: 610, radius: 116, color: _white, antialias: true);

  // A green checkmark inside the ring (white would vanish against the
  // white page behind it). Stroked as a dense run of overlapping filled
  // circles rather than a thick drawLine, which bands/hatches badly at
  // this thickness.
  const p1 = (548.0, 610.0);
  const p2 = (592.0, 656.0);
  const p3 = (682.0, 556.0);
  canvas = _strokePath(canvas, [p1, p2, p3], radius: 15, color: _green);

  return canvas;
}

/// Draws a thick, smooth stroke through [points] by filling densely
/// overlapping circles along each segment - avoids the banding artifacts
/// a thick antialiased [img.drawLine] produces on diagonals.
img.Image _strokePath(
  img.Image canvas,
  List<(double, double)> points, {
  required int radius,
  required img.Color color,
}) {
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final dx = b.$1 - a.$1;
    final dy = b.$2 - a.$2;
    final dist = math.sqrt(dx * dx + dy * dy);
    final steps = dist == 0 ? 1 : (dist / (radius * 0.5)).ceil().clamp(1, 200);
    for (var s = 0; s <= steps; s++) {
      final t = s / steps;
      final x = (a.$1 + dx * t).round();
      final y = (a.$2 + dy * t).round();
      canvas = img.fillCircle(canvas, x: x, y: y, radius: radius, color: color, antialias: true);
    }
  }
  return canvas;
}
