import 'package:flutter/material.dart';

import '../theme.dart';
import 'capture_screen.dart';
import 'scans_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (r) => AppColors.grad.createShader(r),
                  child: const Icon(
                    Icons.document_scanner_outlined,
                    size: 96,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'PaperScanner',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: c.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'Scan pages with your camera, crop and rotate each one, '
                  'then save them all as a PDF.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: c.muted),
                ),
                const SizedBox(height: 32),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    PrimaryButton(
                      icon: Icons.camera_alt,
                      label: 'Start scan',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CaptureScreen(),
                          ),
                        );
                      },
                    ),
                    SecondaryButton(
                      icon: Icons.history,
                      label: 'Scans',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ScansScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
