import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scan.dart';
import '../services/pdf_service.dart';
import '../state/scan_store.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import 'capture_screen.dart';
import 'edit_screen.dart';

/// One saved scan: its pages, with Edit / Add page / Save / Share.
class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.scan});

  final Scan scan;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen> {
  final PdfService _pdf = PdfService();
  String? _working; // 'save' | 'share' while a PDF is being made

  Scan get scan => widget.scan;

  /// Walks through the pages starting at [start]: each is opened in the
  /// crop/rotate screen, Next applies it and moves on, Apply applies and
  /// stops, Cancel discards that page's changes and stops.
  Future<void> _editFrom(int start) async {
    var i = start;
    while (i < scan.pages.length) {
      if (!mounted) return;
      final page = scan.pages[i];
      final result = await Navigator.of(context).push<EditResult>(
        MaterialPageRoute(
          builder: (_) => EditScreen(
            original: scan.originalOf(page),
            initialTurns: page.turns,
            initialCrop: page.crop,
            captureMode: false,
            hasNext: i < scan.pages.length - 1,
            title: 'Page ${i + 1} of ${scan.pages.length}',
          ),
        ),
      );
      if (result == null || !mounted) return;
      await scan.updatePage(i, result.turns, result.crop, result.jpeg);
      if (result.outcome == EditOutcome.stop) return;
      i++;
    }
  }

  Future<void> _addPage() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => CaptureScreen(scan: scan)));
  }

  Future<void> _removePage(int index) async {
    final ok = await confirm(
      context,
      title: 'Remove page ${index + 1}?',
      message: 'This deletes the page and its original photo.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    final store = context.read<ScanStore>();
    final navigator = Navigator.of(context);
    if (scan.pages.length == 1) {
      await store.delete(scan);
      navigator.pop();
    } else {
      await scan.removePage(index);
    }
  }

  Future<void> _run(String kind, Future<String> Function() action) async {
    setState(() => _working = kind);
    try {
      final message = await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not ${kind == 'save' ? 'save' : 'share'} the PDF: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _onSave() => _run('save', () async {
    final name = await _pdf.saveToDownloads(scan.renderedFiles);
    return 'Saved to Downloads: $name';
  });

  Future<void> _onShare() => _run('share', () async {
    final name = await _pdf.saveAndShare(scan.renderedFiles);
    return name != null
        ? 'A copy was saved to Downloads: $name'
        : 'Could not save a copy to Downloads';
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return ListenableBuilder(
      listenable: scan,
      builder: (context, _) {
        final pages = scan.pages;
        final busy = _working != null;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              '${scan.title} · ${pages.length} page${pages.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                    itemCount: pages.length,
                    itemBuilder: (context, i) => Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTap: busy ? null : () => _editFrom(i),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(
                                kButtonRadius,
                              ),
                              border: Border.all(color: c.line),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.file(
                              scan.renderedOf(pages[i]),
                              fit: BoxFit.contain,
                              cacheWidth: 400,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: busy ? null : () => _removePage(i),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              icon: Icons.download,
                              label: 'Save',
                              busy: _working == 'save',
                              onPressed: busy || pages.isEmpty ? null : _onSave,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PrimaryButton(
                              icon: Icons.share,
                              label: 'Share',
                              busy: _working == 'share',
                              onPressed: busy || pages.isEmpty
                                  ? null
                                  : _onShare,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SecondaryButton(
                              icon: Icons.crop_rotate,
                              label: 'Edit',
                              onPressed: busy || pages.isEmpty
                                  ? null
                                  : () => _editFrom(0),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SecondaryButton(
                              icon: Icons.add_a_photo_outlined,
                              label: 'Add page',
                              onPressed: busy ? null : _addPage,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
