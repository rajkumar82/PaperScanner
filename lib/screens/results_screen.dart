import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/scan_session.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _annotated = true;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ScanSession>();
    final pageCount = session.pages.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Total')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${session.runningTotal}',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '$pageCount page${pageCount == 1 ? '' : 's'} scanned',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                CheckboxListTile(
                  value: _annotated,
                  onChanged: (v) => setState(() => _annotated = v ?? true),
                  title: const Text('Annotated'),
                  subtitle: const Text('Show the recognized numbers on each page in the PDF'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: pageCount == 0 || _sharing ? null : _onShare,
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Text('Share PDF', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onShare() async {
    setState(() => _sharing = true);
    try {
      await context.read<ScanSession>().sharePdf(annotated: _annotated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create the PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
