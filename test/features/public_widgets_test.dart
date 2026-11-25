import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/amas.dart';
import 'package:oneday_app/core/figures.dart';
import 'package:oneday_app/core/providers.dart';
import 'package:oneday_app/core/relays.dart';
import 'package:oneday_app/design_system/design_system.dart';
import 'package:oneday_app/features/amas/amas_screen.dart';
import 'package:oneday_app/features/figures/figures_screen.dart';
import 'package:oneday_app/features/relays/relay_screen.dart';

/// Pumps frames without waiting for endless animations to settle.
Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget home) => MaterialApp(theme: OdTheme.dark(), home: home);

void main() {
  testWidgets('an answer joins the relay', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [relayRepositoryProvider.overrideWithValue(FakeRelays())],
        child: _app(const RelayScreen(momentId: 'm1')),
      ),
    );
    await _settle(tester);
    expect(find.text('Kabir'), findsOneWidget);
    expect(find.text('You'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Same sunrise here');
    await tester.tap(find.bySemanticsLabel('Add to the relay'));
    await _settle(tester);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('a figure found by handle can be followed', (tester) async {
    final figures = FakeFigures();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [figuresRepositoryProvider.overrideWithValue(figures)],
        child: _app(const FiguresScreen()),
      ),
    );
    await _settle(tester);
    expect(find.text('Week 12: Meghalaya. Jadoh tonight.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '@kerala.blasters');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    expect(find.text('Follow'), findsOneWidget);

    await tester.tap(find.text('Follow'));
    await _settle(tester);
    expect(
      (await figures.following()).map((f) => f.handle),
      contains('kerala.blasters'),
    );
  });

  testWidgets('a live AMA takes a question, and an answered one shows the answer', (
    tester,
  ) async {
    final amas = FakeAmas();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [amasRepositoryProvider.overrideWithValue(amas)],
        child: _app(const AmaScreen(amaId: 'ama1')),
      ),
    );
    await _settle(tester);
    expect(find.text('Kappa and fish curry at my grandmother\'s.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Best street food in Mumbai?');
    await tester.tap(find.text('Ask'));
    await _settle(tester);
    expect(find.text('Best street food in Mumbai?'), findsOneWidget);
    expect(find.text('You asked'), findsOneWidget);
  });
}
