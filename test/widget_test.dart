import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paperscanner/main.dart';

void main() {
  testWidgets('Home screen shows a Start scan button', (WidgetTester tester) async {
    await tester.pumpWidget(const PaperScannerApp());

    expect(find.text('PaperScanner'), findsOneWidget);
    expect(find.text('Start scan'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });
}
