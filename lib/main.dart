import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'state/scan_session.dart';
import 'theme.dart';

void main() {
  runApp(const PaperScannerApp());
}

class PaperScannerApp extends StatelessWidget {
  const PaperScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScanSession(),
      child: MaterialApp(
        title: 'PaperScanner',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
