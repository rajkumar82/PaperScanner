import 'dart:io';

/// One finished page: the user's captured photo after rotate + crop.
class PageResult {
  PageResult({required this.index, required this.file});

  /// 0-based order in the PDF.
  final int index;

  /// The rotated, cropped and resized JPEG used for display and export.
  final File file;
}
