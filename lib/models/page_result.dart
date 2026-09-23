import 'dart:io';

import 'detected_mark.dart';

/// The outcome of capturing and processing a single booklet page.
class PageResult {
  PageResult({
    required this.index,
    required this.rawImageFile,
    this.annotatedImageFile,
    this.marks = const [],
    this.processing = true,
  });

  /// 0-based capture order.
  final int index;

  /// The original full-resolution photo as captured, straight off the
  /// camera. Not used for display/export - too large - kept only in case
  /// a future version wants to re-process a page.
  final File rawImageFile;

  /// The page resized to display/export resolution, without annotations.
  /// Null until processing finishes.
  File? displayImageFile;

  /// A copy of [displayImageFile] with the recognized numbers drawn on top
  /// of the marks that were found. Null until processing finishes.
  File? annotatedImageFile;

  /// Marks found on this page. Empty (once [processing] is false) means no
  /// marks were detected on this page.
  List<DetectedMark> marks;

  /// True while the background detection/OCR pass for this page is still
  /// running.
  bool processing;

  int get subtotal => marks.fold(0, (sum, m) => sum + m.value);

  /// Which image to show/export for this page.
  File displayFile({required bool annotated}) {
    if (annotated && annotatedImageFile != null) {
      return annotatedImageFile!;
    }
    return displayImageFile ?? rawImageFile;
  }
}
