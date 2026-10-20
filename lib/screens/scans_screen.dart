import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scan.dart';
import '../state/scan_store.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import 'scan_detail_screen.dart';

/// Recent scans, newest first.
class ScansScreen extends StatelessWidget {
  const ScansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ScanStore>();
    final c = AppColors.of(context);
    final scans = store.scans;

    return Scaffold(
      appBar: AppBar(title: const Text('Recent scans')),
      body: SafeArea(
        child: !store.loaded
            ? const Center(child: CircularProgressIndicator())
            : scans.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No scans yet.\nTap Start scan to make your first one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 16),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: scans.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _ScanTile(scan: scans[i]),
              ),
      ),
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.scan});

  final Scan scan;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final n = scan.pages.length;

    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(kButtonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kButtonRadius),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => ScanDetailScreen(scan: scan))),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kButtonRadius),
            border: Border.all(color: c.line),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 72,
                decoration: BoxDecoration(
                  color: c.card2,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(
                  scan.renderedOf(scan.pages.first),
                  fit: BoxFit.cover,
                  cacheWidth: 200,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scan.title,
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$n page${n == 1 ? '' : 's'}',
                      style: TextStyle(color: c.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete scan',
                icon: Icon(Icons.delete_outline, color: c.muted),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Delete this scan?',
                    message:
                        'The ${scan.pages.length} page(s) from ${scan.title} will be removed from this device. PDFs you already saved are not affected.',
                    action: 'Delete',
                  );
                  if (ok && context.mounted) {
                    await context.read<ScanStore>().delete(scan);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
