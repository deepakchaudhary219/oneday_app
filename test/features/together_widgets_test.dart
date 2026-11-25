import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/dates.dart';
import 'package:oneday_app/core/plans.dart';
import 'package:oneday_app/core/prompts.dart';
import 'package:oneday_app/core/providers.dart';
import 'package:oneday_app/core/pulse_status.dart';
import 'package:oneday_app/design_system/design_system.dart';
import 'package:oneday_app/features/dates/dates_screen.dart';
import 'package:oneday_app/features/plans/plans_screen.dart';
import 'package:oneday_app/features/together/together_screen.dart';

/// Pumps frames without waiting for endless animations to settle.
Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget home) => MaterialApp(theme: OdTheme.dark(), home: home);

void main() {
  testWidgets('answering today\'s prompt opens the nearby answers', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          promptRepositoryProvider.overrideWithValue(FakePrompts()),
          pulseRepositoryProvider.overrideWithValue(FakePulse()),
        ],
        child: _app(const TogetherScreen()),
      ),
    );
    await _settle(tester);
    expect(
      find.text('What does your street smell like at 7 am?'),
      findsOneWidget,
    );
    expect(find.text('Riya · chai'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Filter coffee and jasmine');
    await tester.tap(find.text('Answer nearby'));
    await _settle(tester);
    expect(find.text('Riya · chai'), findsOneWidget);
  });

  testWidgets('a plan nearby can be opened and joined', (tester) async {
    final plans = FakePlans();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [plansRepositoryProvider.overrideWithValue(plans)],
        child: _app(const PlansScreen()),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Sunday badminton doubles'));
    await _settle(tester);
    await tester.tap(find.text('Ask to join'));
    await _settle(tester);

    expect((await plans.mine()).single.id, 'pl1');
    expect(find.text('Room'), findsOneWidget);
  });

  testWidgets('an invitation can be accepted, and SOS asks before it sends', (
    tester,
  ) async {
    final dates = FakeDates();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [datesRepositoryProvider.overrideWithValue(dates)],
        child: _app(const DatesScreen()),
      ),
    );
    await _settle(tester);
    expect(find.text('With Riya'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await _settle(tester);
    expect((await dates.list()).single.confirmed, isTrue);

    await tester.tap(find.text('SOS'));
    await _settle(tester, 6);
    expect(dates.sosRaised, isFalse);
    await tester.tap(find.text('Send SOS'));
    await _settle(tester, 6);
    expect(dates.sosRaised, isTrue);
  });
}
