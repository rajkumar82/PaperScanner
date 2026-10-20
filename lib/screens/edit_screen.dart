import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../theme.dart';

/// What the user chose after editing a page.
enum EditOutcome { next, stop }

/// Longest side of an exported page, in pixels.
const int _maxSide = 2200;

/// The user's choices for a page, plus its rendered (rotated + cropped)
/// JPEG. Returned by [EditScreen]; null means the user backed out.
class EditResult {
  EditResult(this.outcome, this.turns, this.crop, this.jpeg);

  final EditOutcome outcome;
  final int turns;
  final Rect crop;
  final Uint8List jpeg;
}

/// Crop + rotate one photo. In [captureMode] (a fresh shot) the buttons are
/// Retake / Stop / Next; otherwise (re-editing a saved page) they are
/// Cancel / Apply / Next, and Next only shows when [hasNext].
class EditScreen extends StatefulWidget {
  const EditScreen({
    super.key,
    required this.original,
    this.initialTurns = 0,
    this.initialCrop,
    this.captureMode = true,
    this.hasNext = true,
    this.title = 'Crop & rotate',
  });

  final File original;
  final int initialTurns;
  final Rect? initialCrop;
  final bool captureMode;
  final bool hasNext;
  final String title;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  ImageProvider? _provider; // the photo as captured
  Size _size = Size.zero; // displayed pixel size (EXIF-oriented)
  late int _turns = widget.initialTurns; // clockwise quarter turns on the photo
  // Crop rectangle in the *displayed* (rotated) image, as 0..1 fractions.
  late Rect _crop = widget.initialCrop ?? const Rect.fromLTRB(0, 0, 1, 1);
  bool _saving = false;
  bool _dragging = false; // a crop drag is in progress: ignore system back
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Shows the photo straight away: Flutter decodes it natively (and applies
  /// its EXIF rotation), which is near-instant. The slow pure-Dart
  /// decode/crop/encode only happens once, when the user taps Next/Stop.
  Future<void> _load() async {
    final provider = FileImage(widget.original);
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!mounted) return;
        setState(() {
          _provider = provider;
          _size = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      },
      onError: (e, _) {
        stream.removeListener(listener);
        if (mounted) setState(() => _loadError = e.toString());
      },
    );
    stream.addListener(listener);
  }

  void _rotate(bool clockwise) {
    final c = _crop;
    setState(() {
      _turns = (_turns + (clockwise ? 1 : 3)) % 4;
      _crop = clockwise
          ? Rect.fromLTRB(1 - c.bottom, c.left, 1 - c.top, c.right)
          : Rect.fromLTRB(c.top, 1 - c.right, c.bottom, 1 - c.left);
    });
  }

  Future<void> _commit(EditOutcome outcome) async {
    if (_provider == null || _saving) return;
    setState(() => _saving = true);
    try {
      final jpeg = await compute(_render, (
        path: widget.original.path,
        turns: _turns,
        l: _crop.left,
        t: _crop.top,
        r: _crop.right,
        b: _crop.bottom,
      ));
      if (mounted) {
        Navigator.of(context).pop(EditResult(outcome, _turns, _crop, jpeg));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not process the page: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final aspect = _turns.isOdd
        ? _size.height / _size.width
        : _size.width / _size.height;
    final ready = provider != null && !_saving;

    return PopScope(
      canPop: !_dragging,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Rotate left',
              onPressed: ready ? () => _rotate(false) : null,
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton(
              tooltip: 'Rotate right',
              onPressed: ready ? () => _rotate(true) : null,
              icon: const Icon(Icons.rotate_right),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _loadError != null
                    ? Center(
                        child: Text(
                          'Could not read the photo:\n$_loadError',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : provider == null
                    ? const Center(child: CircularProgressIndicator())
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 24,
                        ),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: aspect,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                RotatedBox(
                                  quarterTurns: _turns,
                                  child: Image(
                                    image: provider,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                _CropOverlay(
                                  rect: _crop,
                                  onChanged: (r) => setState(() => _crop = r),
                                  onDragging: (v) =>
                                      setState(() => _dragging = v),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  children: [
                    SecondaryButton(
                      icon: widget.captureMode ? Icons.replay : Icons.close,
                      label: widget.captureMode ? 'Retake' : 'Cancel',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    if (widget.hasNext) ...[
                      SecondaryButton(
                        icon: widget.captureMode ? Icons.stop : Icons.check,
                        label: widget.captureMode ? 'Stop' : 'Apply',
                        onPressed: ready
                            ? () => _commit(EditOutcome.stop)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      PrimaryButton(
                        icon: Icons.arrow_forward,
                        label: 'Next',
                        busy: _saving,
                        onPressed: ready
                            ? () => _commit(EditOutcome.next)
                            : null,
                      ),
                    ] else
                      PrimaryButton(
                        icon: widget.captureMode ? Icons.stop : Icons.check,
                        label: widget.captureMode ? 'Stop' : 'Apply',
                        busy: _saving,
                        onPressed: ready
                            ? () => _commit(EditOutcome.stop)
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draggable crop rectangle: drag a corner to resize, drag inside to move.
class _CropOverlay extends StatefulWidget {
  const _CropOverlay({
    required this.rect,
    required this.onChanged,
    required this.onDragging,
  });

  final Rect rect;
  final ValueChanged<Rect> onChanged;
  final ValueChanged<bool> onDragging;

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  static const double _grab = 56; // px radius for grabbing a corner
  static const double _minFrac = 0.08;

  int? _corner; // 0 TL, 1 TR, 2 BR, 3 BL
  bool _moving = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        Rect px(Rect f) => Rect.fromLTRB(
          f.left * size.width,
          f.top * size.height,
          f.right * size.width,
          f.bottom * size.height,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            widget.onDragging(true);
            final r = px(widget.rect);
            final corners = [
              r.topLeft,
              r.topRight,
              r.bottomRight,
              r.bottomLeft,
            ];
            int? best;
            var bestDist = _grab;
            for (var i = 0; i < 4; i++) {
              final dist = (corners[i] - d.localPosition).distance;
              if (dist < bestDist) {
                best = i;
                bestDist = dist;
              }
            }
            _corner = best;
            _moving = best == null && r.contains(d.localPosition);
          },
          onPanEnd: (_) => widget.onDragging(false),
          onPanCancel: () => widget.onDragging(false),
          onPanUpdate: (d) {
            final dx = d.delta.dx / size.width;
            final dy = d.delta.dy / size.height;
            final r = widget.rect;
            if (_corner != null) {
              var l = r.left, t = r.top, rr = r.right, b = r.bottom;
              if (_corner == 0 || _corner == 3) {
                l = (l + dx).clamp(0.0, rr - _minFrac);
              }
              if (_corner == 1 || _corner == 2) {
                rr = (rr + dx).clamp(l + _minFrac, 1.0);
              }
              if (_corner == 0 || _corner == 1) {
                t = (t + dy).clamp(0.0, b - _minFrac);
              }
              if (_corner == 2 || _corner == 3) {
                b = (b + dy).clamp(t + _minFrac, 1.0);
              }
              widget.onChanged(Rect.fromLTRB(l, t, rr, b));
            } else if (_moving) {
              final mx = dx.clamp(-r.left, 1 - r.right);
              final my = dy.clamp(-r.top, 1 - r.bottom);
              widget.onChanged(r.shift(Offset(mx, my)));
            }
          },
          child: CustomPaint(
            size: size,
            painter: _CropPainter(px(widget.rect)),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black54);

    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    final grid = Paint()
      ..strokeWidth = 1
      ..color = Colors.white38;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }

    // Big, see-through purple handles so the image underneath stays visible.
    final fill = Paint()..color = AppColors.accent2.withValues(alpha: 0.35);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.accent2.withValues(alpha: 0.9);
    for (final c in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      canvas.drawCircle(c, 18, fill);
      canvas.drawCircle(c, 18, ring);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}

// ---- isolate work ---------------------------------------------------------

/// Rotates, crops and downsizes the original photo into the exported page.
Uint8List _render(
  ({String path, int turns, double l, double t, double r, double b}) a,
) {
  var image = img.decodeImage(File(a.path).readAsBytesSync());
  if (image == null) throw const FormatException('Unreadable photo');
  image = img.bakeOrientation(image);
  if (a.turns != 0) image = img.copyRotate(image, angle: a.turns * 90);
  final x = (a.l * image.width).round().clamp(0, image.width - 1);
  final y = (a.t * image.height).round().clamp(0, image.height - 1);
  final w = ((a.r - a.l) * image.width).round().clamp(1, image.width - x);
  final h = ((a.b - a.t) * image.height).round().clamp(1, image.height - y);
  image = img.copyCrop(image, x: x, y: y, width: w, height: h);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: _maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: _maxSide,
            interpolation: img.Interpolation.average,
          );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}
