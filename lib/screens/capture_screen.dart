import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/page_result.dart';
import '../services/page_locator.dart';
import '../state/scan_session.dart';
import 'results_screen.dart';

/// How often to try a shot while [_Phase.searching].
const Duration _pollInterval = Duration(milliseconds: 800);

enum _Phase {
  /// Actively polling the camera, looking for a well-framed page.
  searching,

  /// A page was just found and captured; waiting for the user to tap Next
  /// before searching for the following page.
  found,
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _controller;
  bool _initializing = true;
  String? _error;
  String? _sessionDir;
  int _captureCount = 0;
  _Phase _phase = _Phase.searching;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final session = context.read<ScanSession>();
      _sessionDir = await session.start();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera was found on this device.');
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        // `high` is only ~720p, not enough detail for small hand-drawn
        // circles once the page is downsized further for the search pass -
        // that was the main reason real captures were finding no marks at
        // all. `veryHigh` (~1080p) gives meaningfully more pixels to work
        // with without the capture/processing cost of `max`.
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await controller.initialize();
      // Widest field of view available (min zoom) - on the gooseneck stand
      // the constraint is holding the phone far enough up that the whole
      // page fits in frame, so we want as much frame as possible rather
      // than a tighter/zoomed-in shot.
      try {
        final minZoom = await controller.getMinZoomLevel();
        await controller.setZoomLevel(minZoom);
      } catch (e) {
        debugPrint('Could not set zoom level: $e');
      }
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      unawaited(_pollLoop());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.toString();
      });
    }
  }

  /// While [_phase] is [_Phase.searching], repeatedly takes a still photo
  /// and tries to find+crop a page in it, roughly every [_pollInterval].
  /// Stops itself as soon as a page is found (or the screen is gone).
  Future<void> _pollLoop() async {
    while (mounted && _phase == _Phase.searching) {
      await _tryCaptureOnce();
      if (!mounted || _phase != _Phase.searching) return;
      await Future.delayed(_pollInterval);
    }
  }

  Future<void> _tryCaptureOnce() async {
    final controller = _controller;
    final sessionDir = _sessionDir;
    if (controller == null || sessionDir == null || _capturing) return;
    if (!controller.value.isInitialized || controller.value.isTakingPicture) return;

    _capturing = true;
    try {
      // Trigger a fresh autofocus at the centre of the frame and give the
      // lens a moment to settle before capturing, rather than trusting
      // whatever focus state continuous AF happens to be in at this exact
      // instant - this was producing genuinely blurry accepted shots.
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await Future.delayed(const Duration(milliseconds: 450));
      } catch (e) {
        debugPrint('Could not trigger focus: $e');
      }

      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();

      // Finds the page, perspective-corrects and crops to just that
      // region - or returns null if nothing page-like was found yet.
      // Everything downstream (detection and the exported PDF) works from
      // this cropped image, never the raw uncropped photo.
      final cropped = await locateAndCropPage(bytes);
      if (cropped == null || !mounted) return;

      final destPath = p.join(sessionDir, 'raw_${_captureCount++}.jpg');
      await File(destPath).writeAsBytes(cropped, flush: true);
      if (!mounted) return;

      setState(() => _phase = _Phase.found);
      unawaited(context.read<ScanSession>().addCapturedPage(File(destPath)));
    } catch (e) {
      debugPrint('Capture attempt failed: $e');
    } finally {
      _capturing = false;
    }
  }

  void _onNext() {
    setState(() => _phase = _Phase.searching);
    unawaited(_pollLoop());
  }

  Future<void> _onStop() async {
    final controller = _controller;
    setState(() => _controller = null);
    if (controller != null) {
      await controller.dispose();
    }
    if (!mounted) return;
    final session = context.read<ScanSession>();
    session.stop();
    if (session.pages.isEmpty) {
      // Nothing was captured - no point showing a "Total: 0" screen with
      // nothing to share, just go back to the start.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ResultsScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PaperScanner')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text('Could not start the camera:\n$_error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _initializing = true;
                    });
                    _init();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_initializing || _controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = context.watch<ScanSession>();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.summarize, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Total: ${session.runningTotal}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '(${session.pages.length} page${session.pages.length == 1 ? '' : 's'})',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_phase == _Phase.searching)
            Positioned(
              left: 0,
              right: 0,
              bottom: 190,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      ),
                      SizedBox(width: 10),
                      Text('Looking for a page...', style: TextStyle(color: Colors.white, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            bottom: 110,
            child: _LastPageThumbnail(pages: session.pages),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_phase == _Phase.found) ...[
                  FilledButton.icon(
                    onPressed: _onNext,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      child: Text('Next', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: _onStop,
                  icon: const Icon(Icons.stop),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    child: Text('Stop', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the most recently captured page: a spinner while its detection
/// pass is still running, then the annotated thumbnail with its subtotal
/// (or "-0-" if nothing was found on it) once ready.
class _LastPageThumbnail extends StatelessWidget {
  const _LastPageThumbnail({required this.pages});

  final List<PageResult> pages;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) return const SizedBox.shrink();
    final page = pages.last;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey('${page.index}-${page.processing}'),
        width: 90,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white70, width: 2),
          color: Colors.black54,
        ),
        clipBehavior: Clip.antiAlias,
        child: page.processing
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(page.displayFile(annotated: true), fit: BoxFit.cover),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        page.marks.isEmpty ? '-0-' : '${page.subtotal}',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
