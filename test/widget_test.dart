import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paperscanner/main.dart';

void main() {
  testWidgets('Home screen shows a Start button', (WidgetTester tester) async {
    await tester.pumpWidget(const PaperScannerApp());

    expect(find.text('PaperScanner'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
