/// A single mark (a number a teacher circled in red ink) found on a page.
class DetectedMark {
  DetectedMark({
    required this.value,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// The recognized integer value, e.g. the "3" inside a red circle.
  final int value;

  /// Location of the mark on the page image (full-resolution pixel
  /// coordinates), used to draw the annotation on top of it.
  final int x;
  final int y;
  final int width;
  final int height;
}
