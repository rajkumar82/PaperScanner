import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scan.dart';
import '../state/scan_store.dart';
import '../theme.dart';
import 'edit_screen.dart';
import 'scan_detail_screen.dart';

/// Live camera preview with a shutter button. Each shot goes to the
/// [EditScreen] for crop/rotate, then the user either continues scanning or
/// stops and saves.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.scan});

  /// An existing scan to add pages to; null starts a new scan.
  final Scan? scan;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _controller;
  bool _initializing = true;
  String? _error;
  bool _busy = false;
  Scan? _scan; // created lazily on the first page, so empty scans never exist

  @override
  void initState() {
    super.initState();
    _scan = widget.scan;
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
          'no_camera',
          'No camera was found on this device.',
        );
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.ultraHigh,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onShutter() async {
    final controller = _controller;
    if (controller == null || _busy || !controller.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      // Let autofocus settle on the centre before shooting.
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await Future.delayed(const Duration(milliseconds: 400));
      } catch (e) {
        debugPrint('Could not trigger focus: $e');
      }
      final shot = await controller.takePicture();
      if (!mounted) return;

      final photo = File(shot.path);
      final result = await Navigator.of(context).push<EditResult>(
        MaterialPageRoute(builder: (_) => EditScreen(original: photo)),
      );
      if (result == null || !mounted) return; // retake

      final store = context.read<ScanStore>();
      final scan = _scan ??= await store.create();
      await scan.addPage(photo, result.turns, result.crop, result.jpeg);
      store.register(scan);
      if (!mounted) return;
      setState(() {});
      if (result.outcome == EditOutcome.stop) {
        await _finish();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not take the photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaves the camera: back to the scan when adding pages to an existing
  /// one, otherwise on to the new scan's page.
  Future<void> _finish() async {
    final scan = _scan;
    final controller = _controller;
    setState(() => _controller = null);
    await controller?.dispose();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (widget.scan != null || scan == null) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => ScanDetailScreen(scan: scan)),
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
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  'Could not start the camera:\n$_error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Retry',
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _initializing = true;
                    });
                    _init();
                  },
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

    final pages = _scan?.pages ?? const <ScanPage>[];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: CameraPreview(_controller!)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(kButtonRadius),
                  ),
                  child: Text(
                    '${pages.length} page${pages.length == 1 ? '' : 's'} scanned',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: pages.isEmpty
                          ? const SizedBox.shrink()
                          : Container(
                              width: 56,
                              height: 72,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white70,
                                  width: 2,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.file(
                                _scan!.renderedOf(pages.last),
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _busy ? null : _onShutter,
                    child: Container(
                      width: 76,
                      height: 76,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _busy ? null : AppColors.grad,
                          color: _busy ? Colors.white38 : null,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: pages.isEmpty
                          ? const SizedBox.shrink()
                          : SecondaryButton(
                              overCamera: true,
                              icon: Icons.stop,
                              label: 'Stop',
                              onPressed: _busy ? null : _finish,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
