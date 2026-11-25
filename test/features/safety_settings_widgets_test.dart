import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/providers.dart';
import 'package:oneday_app/core/safety.dart';
import 'package:oneday_app/core/settings.dart';
import 'package:oneday_app/design_system/design_system.dart';
import 'package:oneday_app/features/safety/safety_sheet.dart';
import 'package:oneday_app/features/settings/settings_screen.dart';

/// Pumps frames without waiting for endless animations to settle.
Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('the safety sheet', () {
    late FakeSafety safety;
    SafetyOutcome? outcome;

    Future<void> open(WidgetTester tester) async {
      safety = FakeSafety();
      outcome = null;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [safetyRepositoryProvider.overrideWithValue(safety)],
          child: MaterialApp(
            theme: OdTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      outcome = await showSafetySheet(
                        context,
                        target: const SafetyTarget.connection('c1'),
                        firstName: 'Riya',
                        connectionId: 'c1',
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    testWidgets('blocking asks first, then blocks and closes', (tester) async {
      await open(tester);

      await tester.tap(find.text('Block'));
      await _settle(tester, 4);
      expect(find.text('Block Riya?'), findsOneWidget);
      expect(safety.blocked, isEmpty);

      await tester.tap(find.text('Block'));
      await _settle(tester);
      expect(safety.blocked.single.id, 'c1');
      expect(outcome, SafetyOutcome.blocked);
      expect(find.text('Block Riya?'), findsNothing);
    });

    testWidgets('a report needs a category and blocks too by default', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Report'));
      await _settle(tester, 4);
      await tester.tap(find.text('Harassment or bullying'));
      await tester.pump();
      await tester.ensureVisible(find.text('Send report'));
      await tester.pump();
      await tester.tap(find.text('Send report'));
      await _settle(tester);

      final (target, category, _, alsoBlock) = safety.reported.single;
      expect(target.field, 'connectionId');
      expect(category, ReportCategory.harassment);
      expect(alsoBlock, isTrue);
      expect(outcome, SafetyOutcome.blocked);
    });

    testWidgets('leaving quietly is offered for a connection', (tester) async {
      await open(tester);

      await tester.tap(find.text('Leave quietly'));
      await _settle(tester, 4);
      await tester.tap(find.text('Leave quietly'));
      await _settle(tester);

      expect(safety.left, ['c1']);
      expect(outcome, SafetyOutcome.left);
    });
  });

  group('settings', () {
    late FakeSettings settings;

    Future<void> open(WidgetTester tester) async {
      settings = FakeSettings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
          child: MaterialApp(
            theme: OdTheme.dark(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await _settle(tester);
    }

    testWidgets('load the preferences, and the Dating Lens switch saves', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Nearby reaches 5 km'), findsOneWidget);

      await tester.tap(find.text('Dating Lens'));
      await _settle(tester, 4);
      expect((await settings.preferences()).datingLens, isTrue);
    });

    testWidgets('withdrawing a consent says what it deletes and asks first', (
      tester,
    ) async {
      await open(tester);

      final purpose = find.text('Location for Nearby');
      await tester.scrollUntilVisible(purpose, 200);
      await tester.tap(purpose);
      await _settle(tester, 6);
      expect(
        find.text('Your area is deleted and you leave Nearby and the map.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Withdraw'));
      await _settle(tester);
      final location = (await settings.consents()).firstWhere(
        (p) => p.purpose == 'LOCATION_DISCOVERY',
      );
      expect(location.granted, isFalse);
    });
  });
}
