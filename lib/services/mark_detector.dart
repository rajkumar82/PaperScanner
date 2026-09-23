import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A digit ML Kit found somewhere on the page (any colour, any location) -
/// before we've checked whether it's actually circled in red.
class OcrHit {
  OcrHit({
    required this.value,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int value;
  final double left, top, right, bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}

/// An [OcrHit] confirmed to sit inside a red ring.
class VerifiedMark {
  VerifiedMark({
    required this.value,
    required this.displayX,
    required this.displayY,
    required this.displayWidth,
    required this.displayHeight,
    required this.debugInfo,
  });

  final int value;

  /// The ring's bounding box in display-resolution coordinates, used to
  /// place the annotation.
  final int displayX, displayY, displayWidth, displayHeight;

  final String debugInfo;
}

class MarkVerificationResult {
  MarkVerificationResult({
    required this.displayImageJpeg,
    required this.displayWidth,
    required this.displayHeight,
    required this.marks,
    required this.stats,
  });

  /// The page photo, resized to a display/export resolution (this is what
  /// gets shown on screen and embedded in the PDF - the full camera photo
  /// is too large for that).
  final Uint8List displayImageJpeg;
  final int displayWidth;
  final int displayHeight;

  final List<VerifiedMark> marks;
  final VerificationStats stats;
}

class VerificationStats {
  VerificationStats({
    required this.ocrHits,
    required this.redHits,
    required this.ringVerified,
  });

  /// How many digit-parseable text elements ML Kit found on the page at
  /// all, regardless of colour or whether they're circled.
  final int ocrHits;

  /// Of those, how many had any red ink at all near them.
  final int redHits;

  /// Of those, how many were actually surrounded by a red ring - the
  /// final confirmed marks.
  final int ringVerified;

  @override
  String toString() => 'ocrHits=$ocrHits redHits=$redHits verified=$ringVerified';
}

// --- Tunable constants -----------------------------------------------

/// Long side, in pixels, of the copy used for on-screen display and for
/// the exported PDF.
const int kDisplayWidth = 1600;

/// The scale a page-wide search copy would have used, applied to each
/// small per-digit window too - keeps the shape thresholds below
/// (calibrated at that scale) meaningful regardless of the source photo's
/// actual resolution.
const int kSearchWidth = 1100;

/// Red-ness thresholds. LAB a* channel (green<->red axis) is far more
/// stable across lighting changes than a raw HSV/RGB threshold. Combined
/// with a simple "excess red" (R minus the stronger of G/B) check so
/// faint/brownish shadows don't get picked up.
const double kAStarThreshold = 10.0;
const int kExcessRedThreshold = 16;

/// Radius (px, local search-resolution) used to lightly dilate the red
/// mask - just enough to bridge antialiasing/JPEG gaps within a single
/// stroke, not enough to merge separate marks together.
const int kDilateRadius = 2;

/// Ignore tiny flecks of red - not big enough to be a stroke of a circle.
const int kMinBlobPixels = 25;

/// A blob is treated as "circled" by its shape rather than by requiring a
/// literal enclosed hole (fragile: sensitive to gaps and to dilation
/// merging nearby unrelated ink): every pixel's distance from the blob's
/// own centroid should be roughly the same - that's what a ring (or a
/// multi-digit oval) looks like, and it tolerates a real gap in the
/// stroke naturally.
///
/// Coefficient of variation (stddev / mean) of that per-pixel radius,
/// maximum allowed for a blob to count as ring-shaped. Calibrated against
/// real hand-drawn circles rather than just a perfect synthetic circle
/// (cv 0.05) - real ones came in around 0.10-0.37, with contaminated/
/// non-ring blobs starting around 0.51.
const double kMaxRingCv = 0.42;

/// Minimum fraction of a full circle (in [kAngleBins] buckets) a blob's
/// ink must actually cover around its own centroid - catches a short,
/// evenly-curved arc/tick that [kMaxRingCv] alone can miss (it can
/// coincidentally have low radius variance too, without going anywhere
/// near all the way around like a real, even gapped, circle does).
const double kMinAngularCoverage = 0.55;

/// Mean radius (local search-resolution px) has to be in this range - too
/// small is noise, too large is implausible for a hand-drawn circle.
/// Calibrated by tracing real candidates back to their source images:
/// every genuine mark measured 23-33px, every false positive measured
/// 8-15px - a clean gap, with this threshold in the middle of it.
const double kMinRingRadius = 18.0;
const double kMaxRingRadius = 140.0;

/// How generously to pad around an OCR-found digit's own bounding box
/// (as a multiple of the digit's size) when looking for a surrounding red
/// ring - has to comfortably contain a loosely drawn circle.
const double kWindowPaddingMultiplier = 4.0;
const double kMinWindowPad = 40.0;

/// The digit's own centre has to land within this fraction of a
/// candidate ring's radius from that ring's centroid - stops a red ring
/// elsewhere in the window (around a different, nearby mark) from being
/// credited to this digit.
const double kMaxDigitOffsetFraction = 0.85;

/// For each [hits] entry (a digit ML Kit found anywhere on the page),
/// checks whether it's actually sitting inside a red ring. Runs the pixel
/// work on a background isolate via [compute] so the UI thread is never
/// blocked by it. OCR itself has already happened by this point (it's a
/// platform-channel call and has to run on the main isolate) - this step
/// is pure image analysis.
Future<MarkVerificationResult> verifyMarks(Uint8List jpegBytes, List<OcrHit> hits) {
  return compute(_verifyIsolate, _VerifyInput(jpegBytes, hits));
}

class _VerifyInput {
  _VerifyInput(this.jpegBytes, this.hits);
  final Uint8List jpegBytes;
  final List<OcrHit> hits;
}

MarkVerificationResult _verifyIsolate(_VerifyInput input) {
  var original = img.decodeImage(input.jpegBytes);
  if (original == null) {
    throw const FormatException('Could not decode page photo');
  }
  // Normalize actual pixel orientation to match any EXIF rotation tag, so
  // coordinates from ML Kit (which saw the same file) line up.
  original = img.bakeOrientation(original);

  final displayImg = img.copyResize(
    original,
    width: math.min(kDisplayWidth, original.width),
    maintainAspect: true,
    interpolation: img.Interpolation.average,
  );
  final displayScale = displayImg.width / original.width;
  final searchScale = math.min(kSearchWidth, original.width) / original.width;

  var redHits = 0;
  final marks = <VerifiedMark>[];

  for (final hit in input.hits) {
    final padX = math.max(kMinWindowPad, hit.width * kWindowPaddingMultiplier);
    final padY = math.max(kMinWindowPad, hit.height * kWindowPaddingMultiplier);

    final wx0 = (hit.left - padX).clamp(0, original.width - 1).round();
    final wy0 = (hit.top - padY).clamp(0, original.height - 1).round();
    final wx1 = (hit.right + padX).clamp(0.0, original.width.toDouble()).round();
    final wy1 = (hit.bottom + padY).clamp(0.0, original.height.toDouble()).round();
    final ww = (wx1 - wx0).clamp(1, original.width - wx0);
    final wh = (wy1 - wy0).clamp(1, original.height - wy0);
    if (ww < 4 || wh < 4) continue;

    final windowImg = img.copyCrop(original, x: wx0, y: wy0, width: ww, height: wh);
    // Resize to the same effective scale a page-wide search copy would
    // have used, so the calibrated shape thresholds still apply.
    final localWidth = math.max(1, (ww * searchScale).round());
    final localSearch = img.copyResize(
      windowImg,
      width: localWidth,
      maintainAspect: true,
      interpolation: img.Interpolation.average,
    );
    if (localSearch.width < 3 || localSearch.height < 3) continue;
    final localScale = localSearch.width / ww;

    final mask = _buildRedMask(localSearch);
    final hasRed = mask.any((v) => v != 0);
    if (!hasRed) continue;
    redHits++;

    final dilated = _dilate(mask, localSearch.width, localSearch.height, kDilateRadius);
    final blobs = _connectedComponents(dilated, localSearch.width, localSearch.height);

    final digitCx = (hit.centerX - wx0) * localScale;
    final digitCy = (hit.centerY - wy0) * localScale;

    _Blob? best;
    for (final blob in blobs) {
      if (blob.count < kMinBlobPixels) continue;
      if (blob.radiusCv > kMaxRingCv) continue;
      final meanR = blob.meanRadius;
      if (meanR < kMinRingRadius || meanR > kMaxRingRadius) continue;
      if (blob.angularCoverage < kMinAngularCoverage) continue;

      // The digit itself has to actually sit inside this ring, not just
      // be somewhere in the window (which might contain a different
      // nearby mark's ring too).
      final dx = digitCx - blob.centroidX;
      final dy = digitCy - blob.centroidY;
      final offset = math.sqrt(dx * dx + dy * dy);
      if (offset > meanR * kMaxDigitOffsetFraction) continue;

      if (best == null || blob.count > best.count) best = blob;
    }

    if (best != null) {
      final ringMinX = wx0 + best.minX / localScale;
      final ringMinY = wy0 + best.minY / localScale;
      final ringW = best.width / localScale;
      final ringH = best.height / localScale;
      marks.add(VerifiedMark(
        value: hit.value,
        displayX: (ringMinX * displayScale).round(),
        displayY: (ringMinY * displayScale).round(),
        displayWidth: math.max(1, (ringW * displayScale).round()),
        displayHeight: math.max(1, (ringH * displayScale).round()),
        debugInfo: 'v=${hit.value} R${best.meanRadius.toStringAsFixed(0)} cv${best.radiusCv.toStringAsFixed(2)}',
      ));
    }
  }

  return MarkVerificationResult(
    displayImageJpeg: Uint8List.fromList(img.encodeJpg(displayImg, quality: 90)),
    displayWidth: displayImg.width,
    displayHeight: displayImg.height,
    marks: marks,
    stats: VerificationStats(ocrHits: input.hits.length, redHits: redHits, ringVerified: marks.length),
  );
}

// --- Red mask -----------------------------------------------------------

Uint8List _buildRedMask(img.Image image) {
  final mask = Uint8List(image.width * image.height);
  for (final p in image) {
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    final aStar = _labAStar(r, g, b);
    final excessRed = r - math.max(g, b);
    if (aStar > kAStarThreshold && excessRed > kExcessRedThreshold) {
      mask[p.y * image.width + p.x] = 1;
    }
  }
  return mask;
}

/// The LAB a* component (green<->red axis) of an sRGB color. Positive
/// values mean "toward red/magenta". Only the a* term is computed - L*
/// and b* aren't needed here.
double _labAStar(int r, int g, int b) {
  double toLinear(int c) {
    final cs = c / 255.0;
    return cs <= 0.04045 ? cs / 12.92 : math.pow((cs + 0.055) / 1.055, 2.4).toDouble();
  }

  final rl = toLinear(r);
  final gl = toLinear(g);
  final bl = toLinear(b);

  final x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375;
  final y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750;

  double f(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : (7.787 * t) + (16.0 / 116.0);

  final fx = f(x / 0.95047);
  final fy = f(y / 1.00000);
  return 500.0 * (fx - fy);
}

// --- Morphology: separable dilation --------------------------------------

Uint8List _dilate(Uint8List mask, int width, int height, int radius) {
  if (radius <= 0) return mask;
  final horiz = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      var v = 0;
      final lo = math.max(0, x - radius);
      final hi = math.min(width - 1, x + radius);
      for (var xx = lo; xx <= hi; xx++) {
        if (mask[row + xx] != 0) {
          v = 1;
          break;
        }
      }
      horiz[row + x] = v;
    }
  }
  final out = Uint8List(width * height);
  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      var v = 0;
      final lo = math.max(0, y - radius);
      final hi = math.min(height - 1, y + radius);
      for (var yy = lo; yy <= hi; yy++) {
        if (horiz[yy * width + x] != 0) {
          v = 1;
          break;
        }
      }
      out[y * width + x] = v;
    }
  }
  return out;
}

// --- Connected components (two-pass labeling + shape stats) --------------

/// Number of angular buckets (around each blob's own centroid) used to
/// measure how much of a full circle a blob's ink actually covers.
const int kAngleBins = 20;

class _Blob {
  int minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1, count = 0;
  double sumX = 0, sumY = 0;
  double sumDist = 0, sumDistSq = 0;
  final List<bool> angleHit = List.filled(kAngleBins, false);

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
  double get centroidX => sumX / count;
  double get centroidY => sumY / count;
  double get meanRadius => count == 0 ? 0 : sumDist / count;

  /// Coefficient of variation of each pixel's distance from the centroid -
  /// low for a ring (all pixels roughly equidistant from the centre), high
  /// for an irregular or contaminated blob. On its own this doesn't rule
  /// out a short, evenly-curved arc (a stray tick can coincidentally have
  /// low variance too) - [angularCoverage] is what catches that instead.
  double get radiusCv {
    final r = meanRadius;
    if (count == 0 || r == 0) return double.infinity;
    final variance = math.max(0.0, sumDistSq / count - r * r);
    return math.sqrt(variance) / r;
  }

  /// Fraction of the [kAngleBins] directions around the centroid that have
  /// at least one ink pixel - high for something that goes most of the way
  /// around (a circle, even gapped), low for a short arc/tick/stroke that
  /// only occupies a narrow slice of directions.
  double get angularCoverage => angleHit.where((h) => h).length / kAngleBins;
}

class _UnionFind {
  final List<int> parent = [0]; // index 0 unused (0 = background)

  int newLabel() {
    parent.add(parent.length);
    return parent.length - 1;
  }

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
}

List<_Blob> _connectedComponents(Uint8List mask, int width, int height) {
  final labels = Int32List(width * height);
  final uf = _UnionFind();

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final idx = y * width + x;
      if (mask[idx] == 0) continue;
      final left = x > 0 && mask[idx - 1] != 0 ? labels[idx - 1] : 0;
      final top = y > 0 && mask[idx - width] != 0 ? labels[idx - width] : 0;
      if (left == 0 && top == 0) {
        labels[idx] = uf.newLabel();
      } else if (left != 0 && top == 0) {
        labels[idx] = left;
      } else if (left == 0 && top != 0) {
        labels[idx] = top;
      } else {
        labels[idx] = math.min(left, top);
        uf.union(left, top);
      }
    }
  }

  // Pass 2: bounding box + centroid sums per blob.
  final blobsByRoot = <int, _Blob>{};
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final idx = y * width + x;
      final label = labels[idx];
      if (label == 0) continue;
      final root = uf.find(label);
      final blob = blobsByRoot.putIfAbsent(root, () => _Blob());
      if (x < blob.minX) blob.minX = x;
      if (x > blob.maxX) blob.maxX = x;
      if (y < blob.minY) blob.minY = y;
      if (y > blob.maxY) blob.maxY = y;
      blob.count++;
      blob.sumX += x;
      blob.sumY += y;
    }
  }

  // Pass 3: distance- and angle-from-own-centroid, now that centroids are
  // known.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final idx = y * width + x;
      final label = labels[idx];
      if (label == 0) continue;
      final root = uf.find(label);
      final blob = blobsByRoot[root]!;
      final dx = x - blob.centroidX;
      final dy = y - blob.centroidY;
      final d = math.sqrt(dx * dx + dy * dy);
      blob.sumDist += d;
      blob.sumDistSq += d * d;
      if (d > 0.5) {
        final angle = math.atan2(dy, dx); // -pi..pi
        final normalized = (angle + math.pi) / (2 * math.pi); // 0..1
        final bin = (normalized * kAngleBins).floor().clamp(0, kAngleBins - 1);
        blob.angleHit[bin] = true;
      }
    }
  }

  return blobsByRoot.values.toList();
}
