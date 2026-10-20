import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/scan_session.dart';
import '../theme.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String? _working; // 'save' | 'share' while a PDF is being made

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ScanSession>();
    final pages = session.pages;
    final c = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${pages.length} page${pages.length == 1 ? '' : 's'} scanned',
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: pages.length,
                itemBuilder: (context, i) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(kButtonRadius),
                        border: Border.all(color: c.line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(pages[i].file, fit: BoxFit.contain),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _working != null
                              ? null
                              : () => session.removePage(i),
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
                          onPressed: pages.isEmpty || _working != null
                              ? null
                              : _onSave,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrimaryButton(
                          icon: Icons.share,
                          label: 'Share',
                          busy: _working == 'share',
                          onPressed: pages.isEmpty || _working != null
                              ? null
                              : _onShare,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SecondaryButton(
                    label: 'Done',
                    onPressed: _working != null
                        ? null
                        : () =>
                              Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    String kind,
    Future<void> Function(ScanSession) action,
  ) async {
    setState(() => _working = kind);
    try {
      await action(context.read<ScanSession>());
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

  Future<void> _onSave() => _run('save', (session) async {
    final name = await session.savePdf();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved to Downloads: $name')));
  });

  Future<void> _onShare() => _run('share', (session) async {
    final name = await session.saveAndSharePdf();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          name != null
              ? 'A copy was saved to Downloads: $name'
              : 'Could not save a copy to Downloads',
        ),
      ),
    );
  });
}
