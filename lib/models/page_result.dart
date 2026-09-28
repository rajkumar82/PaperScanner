import 'dart:io';

/// The outcome of capturing and processing a single scanned page.
class PageResult {
  PageResult({
    required this.index,
    required this.rawImageFile,
    this.processing = true,
  });

  /// 0-based capture order.
  final int index;

  /// The original full-resolution photo as captured, straight off the
  /// camera. Not used for display/export - too large - kept only in case
  /// a future version wants to re-process a page.
  final File rawImageFile;

  /// The page resized to display/export resolution. Null until processing
  /// finishes.
  File? displayImageFile;

  /// True while the background resize pass for this page is still running.
  bool processing;

  /// Which image to show/export for this page.
  File get displayFile => displayImageFile ?? rawImageFile;
}
