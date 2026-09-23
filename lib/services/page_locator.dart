import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Finds the sheet of paper in a captured photo, perspective-corrects and
/// crops to just that region, and returns the result - or null if no
/// confident page-sized region was found at all (the shutter fired on
/// something that isn't the booklet: the gooseneck stand, a hand, the
/// floor, mid-repositioning).
///
/// This replaces both the earlier coarse "does this look like a page"
/// sanity check and running the mark detector on an uncropped, unskewed
/// photo - background clutter around the page is gone before either the
/// red-circle detector or the exported PDF ever see the image, and the
/// page is deskewed to a straightened rectangle in the process.
///
/// Corners are approximated as the paper-mask pixels that minimise/
/// maximise (x+y) and (x-y) - the standard cheap stand-in for true corner
/// detection when the region is already known to be a single, roughly
/// convex blob. Good enough for a page photographed from close to
/// overhead; not a general-purpose document scanner for steep angles.
Future<Uint8List?> locateAndCropPage(Uint8List jpegBytes) {
  return compute(_locateIsolate, jpegBytes);
}

const int kLocateSearchWidth = 700;
const int kLocateBrightnessThreshold = 110;
const int kLocateMaxChannelSpread = 70;

/// The page blob must cover at least this fraction of the frame...
const double kLocateMinAreaFraction = 0.20;

/// ...and be at least this solid (pixels-in-blob / bounding-box-area).
/// Tuned against real captures: a floor/stand/background shot measured
/// ~0.65, a genuine ink-heavy page as low as ~0.70 - the margin here is
/// genuinely narrow, so treat this as a best-effort filter, not a hard
/// guarantee.
const double kLocateMinFillRatio = 0.68;

/// Max allowed ratio between a quad's two opposite edges (top vs bottom,
/// left vs right) - rejects a lopsided mask (e.g. paper plus a chunk of
/// background it blended into) rather than rectifying it into nonsense.
const double kLocateMaxEdgeRatio = 1.8;

/// Minimum plausible output size (px) - guards against a degenerate/tiny
/// quad being treated as a real page.
const int kLocateMinOutputSize = 300;

/// Minimum gradient-sharpness score (see [_gradientSharpness]) for a
/// candidate crop to be accepted rather than treated as still-blurry.
/// Calibrated against real captures: a genuinely blurry shot measured
/// ~65, sharp ones measured 125-190 - set well below the sharp cluster so
/// a range of real pages (some ink-sparse, some not) all clear it.
const double kLocateMinSharpness = 95.0;

Uint8List? _locateIsolate(Uint8List jpegBytes) {
  var original = img.decodeImage(jpegBytes);
  if (original == null) return null;
  original = img.bakeOrientation(original);

  final small = img.copyResize(
    original,
    width: math.min(kLocateSearchWidth, original.width),
    maintainAspect: true,
    interpolation: img.Interpolation.average,
  );
  final w = small.width, h = small.height;

  final mask = Uint8List(w * h);
  for (final p in small) {
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    final lum = (r + g + b) ~/ 3;
    final spread = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
    if (lum >= kLocateBrightnessThreshold && spread <= kLocateMaxChannelSpread) {
      mask[p.y * w + p.x] = 1;
    }
  }

  final blob = _largestBlobWithCorners(mask, w, h);
  if (blob == null) return null;

  final frameArea = w * h;
  final bboxArea = blob.width * blob.height;
  final areaFraction = bboxArea / frameArea;
  final fillRatio = blob.count / bboxArea;
  if (kDebugMode) {
    debugPrint(
      'locateAndCropPage: areaFraction=${areaFraction.toStringAsFixed(2)} fillRatio=${fillRatio.toStringAsFixed(2)}',
    );
  }
  if (areaFraction < kLocateMinAreaFraction || fillRatio < kLocateMinFillRatio) {
    return null;
  }

  final scale = original.width / w;
  img.Point toOriginal((int, int) p) => img.Point(p.$1 * scale, p.$2 * scale);

  final topLeft = toOriginal(blob.topLeft);
  final topRight = toOriginal(blob.topRight);
  final bottomLeft = toOriginal(blob.bottomLeft);
  final bottomRight = toOriginal(blob.bottomRight);

  double dist(img.Point a, img.Point b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  final topW = dist(topLeft, topRight);
  final bottomW = dist(bottomLeft, bottomRight);
  final leftH = dist(topLeft, bottomLeft);
  final rightH = dist(topRight, bottomRight);

  // A genuine (even quite skewed) page has opposite edges of broadly
  // similar length. A mask that leaked into the background - e.g. paper
  // plus a chunk of a light-coloured bag - produces a lopsided quad
  // instead. Reject rather than rectify something that isn't actually a
  // clean rectangle.
  final widthRatio = math.max(topW, bottomW) / math.max(1.0, math.min(topW, bottomW));
  final heightRatio = math.max(leftH, rightH) / math.max(1.0, math.min(leftH, rightH));
  if (widthRatio > kLocateMaxEdgeRatio || heightRatio > kLocateMaxEdgeRatio) {
    if (kDebugMode) {
      debugPrint('locateAndCropPage: rejected lopsided quad (widthRatio=$widthRatio heightRatio=$heightRatio)');
    }
    return null;
  }

  // Hard cap regardless of the above - never let a bad quad drive an
  // enormous (slow, possibly OOM-ing) output image.
  final maxSide = math.max(original.width, original.height) * 1.5;
  final destWidth = math.max(kLocateMinOutputSize, math.max(topW, bottomW).round()).clamp(kLocateMinOutputSize, maxSide.round());
  final destHeight = math.max(kLocateMinOutputSize, math.max(leftH, rightH).round()).clamp(kLocateMinOutputSize, maxSide.round());

  final dest = img.Image(width: destWidth, height: destHeight, numChannels: original.numChannels);
  img.copyRectify(
    original,
    topLeft: topLeft,
    topRight: topRight,
    bottomLeft: bottomLeft,
    bottomRight: bottomRight,
    interpolation: img.Interpolation.linear,
    toImage: dest,
  );

  final sharpness = _gradientSharpness(dest);
  if (kDebugMode) {
    debugPrint('locateAndCropPage: sharpness=${sharpness.toStringAsFixed(1)}');
  }
  if (sharpness < kLocateMinSharpness) {
    // Shape/colour looked right, but this shot is too blurred to be
    // usable (e.g. taken while the phone was still settling) - keep
    // polling rather than accept it.
    return null;
  }

  return Uint8List.fromList(img.encodeJpg(dest, quality: 92));
}

/// Mean squared gradient between adjacent pixels on a downsampled
/// grayscale copy of [image] - low for a blurred photo, higher once
/// properly focused. Cheap enough to run once per candidate capture
/// (unlike the old per-live-frame gate, this only ever runs after a shape
/// match, not on every preview frame).
double _gradientSharpness(img.Image image) {
  final small = img.copyResize(
    image,
    width: math.min(300, image.width),
    maintainAspect: true,
    interpolation: img.Interpolation.average,
  );
  final w = small.width, h = small.height;
  final luma = Float32List(w * h);
  for (final p in small) {
    luma[p.y * w + p.x] = (p.r + p.g + p.b) / 3;
  }

  var sum = 0.0;
  var n = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = luma[y * w + x];
      if (x + 1 < w) {
        final d = v - luma[y * w + x + 1];
        sum += d * d;
        n++;
      }
      if (y + 1 < h) {
        final d = v - luma[(y + 1) * w + x];
        sum += d * d;
        n++;
      }
    }
  }
  return n == 0 ? 0 : sum / n;
}

class _Blob {
  int minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1, count = 0;
  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;

  // Extremes of (x+y) and (x-y) among the blob's own pixels - the
  // approximate four corners of the (possibly skewed) quadrilateral.
  int minSumX = 0, minSumY = 0, sumMin = 1 << 30;
  int maxSumX = 0, maxSumY = 0, sumMax = -(1 << 30);
  int minDiffX = 0, minDiffY = 0, diffMin = 1 << 30;
  int maxDiffX = 0, maxDiffY = 0, diffMax = -(1 << 30);

  (int, int) get topLeft => (minSumX, minSumY);
  (int, int) get bottomRight => (maxSumX, maxSumY);
  // x - y is largest at the top-right (large x, small y) and smallest at
  // the bottom-left (small x, large y).
  (int, int) get topRight => (maxDiffX, maxDiffY);
  (int, int) get bottomLeft => (minDiffX, minDiffY);

  void addPixel(int x, int y) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    count++;

    final sum = x + y;
    if (sum < sumMin) {
      sumMin = sum;
      minSumX = x;
      minSumY = y;
    }
    if (sum > sumMax) {
      sumMax = sum;
      maxSumX = x;
      maxSumY = y;
    }
    final diff = x - y;
    if (diff < diffMin) {
      diffMin = diff;
      minDiffX = x;
      minDiffY = y;
    }
    if (diff > diffMax) {
      diffMax = diff;
      maxDiffX = x;
      maxDiffY = y;
    }
  }
}

/// Largest 4-connected component of the mask, tracking its corner-ish
/// extremes as it goes.
_Blob? _largestBlobWithCorners(Uint8List mask, int width, int height) {
  final labels = Int32List(width * height);
  final parent = <int>[0];
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final idx = y * width + x;
      if (mask[idx] == 0) continue;
      final left = x > 0 && mask[idx - 1] != 0 ? labels[idx - 1] : 0;
      final top = y > 0 && mask[idx - width] != 0 ? labels[idx - width] : 0;
      if (left == 0 && top == 0) {
        parent.add(parent.length);
        labels[idx] = parent.length - 1;
      } else if (left != 0 && top == 0) {
        labels[idx] = left;
      } else if (left == 0 && top != 0) {
        labels[idx] = top;
      } else {
        labels[idx] = math.min(left, top);
        union(left, top);
      }
    }
  }

  final blobsByRoot = <int, _Blob>{};
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final idx = y * width + x;
      final label = labels[idx];
      if (label == 0) continue;
      final root = find(label);
      final blob = blobsByRoot.putIfAbsent(root, () => _Blob());
      blob.addPixel(x, y);
    }
  }
  if (blobsByRoot.isEmpty) return null;
  return blobsByRoot.values.reduce((a, b) => a.count > b.count ? a : b);
}
