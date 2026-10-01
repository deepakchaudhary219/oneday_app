import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/design_system/design_system.dart';

double _luminance(Color c) => c.computeLuminance();

double contrast(Color a, Color b) {
  final l1 = math.max(_luminance(a), _luminance(b));
  final l2 = math.min(_luminance(a), _luminance(b));
  return (l1 + 0.05) / (l2 + 0.05);
}

void main() {
  group('colour tokens meet WCAG AA for text', () {
    for (final (name, c) in [
      ('dark', OdColors.dark),
      ('light', OdColors.light),
    ]) {
      test('$name: primary and secondary text on canvas and surface', () {
        for (final bg in [c.canvas, c.surface, c.surfaceRaised]) {
          expect(contrast(c.textPrimary, bg), greaterThanOrEqualTo(4.5));
          expect(contrast(c.textSecondary, bg), greaterThanOrEqualTo(4.5));
        }
      });
    }
  });

  testWidgets('a disabled button does nothing and a pressed one fires once', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: OdTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              OdButton(label: 'Go', onPressed: () => taps++),
              const OdButton(label: 'Off', onPressed: null),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.tap(find.text('Off'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
  });

  testWidgets('touch targets are at least 48 dp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OdTheme.dark(),
        home: Scaffold(
          body: Center(
            child: OdIconButton(
              icon: Icons.close,
              semanticLabel: 'Close',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.bySemanticsLabel('Close'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
