import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/capsules.dart';
import 'package:oneday_app/core/device.dart';
import 'package:oneday_app/core/plus_ledger.dart';
import 'package:oneday_app/core/providers.dart';
import 'package:oneday_app/core/right_now.dart';
import 'package:oneday_app/core/threads.dart';
import 'package:oneday_app/design_system/design_system.dart';
import 'package:oneday_app/features/capsules/capsules_screen.dart';
import 'package:oneday_app/features/plus/plus_screen.dart';
import 'package:oneday_app/features/right_now/right_now_screen.dart';
import 'package:oneday_app/features/threads/threads_screen.dart';

/// Pumps frames without waiting for endless animations to settle.
Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(Widget home) => MaterialApp(theme: OdTheme.dark(), home: home);

/// No native checkout in tests, so the link path is what's checked.
class _NoNativeCheckout implements CheckoutLauncher {
  @override
  Future<CheckoutOutcome> open(Checkout checkout) async =>
      const CheckoutOutcome(CheckoutResult.unavailable);
}

void main() {
  testWidgets('Right Now starts, and someone nearby can be asked', (
    tester,
  ) async {
    final rightNow = FakeRightNow();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rightNowRepositoryProvider.overrideWithValue(rightNow)],
        child: _app(const RightNowScreen()),
      ),
    );
    await _settle(tester);

    await tester.enterText(find.byType(TextField), 'badminton');
    await tester.tap(find.text('Start'));
    await _settle(tester);
    expect(find.text('You\'re up for badminton'), findsOneWidget);
    expect(find.text('Kabir'), findsOneWidget);

    await tester.tap(find.text('I\'m in').first);
    await _settle(tester);
    expect(rightNow.asked, contains('rn1'));
  });

  testWidgets('an opened capsule can be read; a sealed one cannot', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          capsuleRepositoryProvider.overrideWithValue(FakeCapsules()),
        ],
        child: _app(const CapsulesScreen()),
      ),
    );
    await _settle(tester);
    expect(find.text('From Riya'), findsOneWidget);
    expect(find.text('To yourself'), findsOneWidget);

    await tester.tap(find.text('From Riya'));
    await _settle(tester);
    expect(
      find.text('One year since Nandi Hills. Same time next year?'),
      findsOneWidget,
    );
  });

  testWidgets('an invitation to a thread can be joined, and then posted to', (
    tester,
  ) async {
    final threads = FakeThreads();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [threadsRepositoryProvider.overrideWithValue(threads)],
        child: _app(const ThreadsScreen()),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Goa trip 🌴'));
    await _settle(tester);
    expect(find.text('Landed! Beach by 4?'), findsNothing);

    await tester.tap(find.text('Join'));
    await _settle(tester);
    expect(find.text('Landed! Beach by 4?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'On my way');
    await tester.tap(find.bySemanticsLabel('Post to the thread'));
    await _settle(tester);
    expect((await threads.posts('t1')).last.caption, 'On my way');
  });

  testWidgets('Plus says what is never sold, and subscribing shows the checkout link', (
    tester,
  ) async {
    final plus = FakePlusLedger();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plusLedgerRepositoryProvider.overrideWithValue(plus),
          checkoutLauncherProvider.overrideWithValue(_NoNativeCheckout()),
        ],
        child: _app(const PlusScreen()),
      ),
    );
    await _settle(tester);
    expect(find.text('Safety features'), findsOneWidget);

    await tester.tap(find.text('Get Plus'));
    await _settle(tester);
    expect(plus.subscribed, isTrue);
    expect(find.text('Finish on Razorpay'), findsOneWidget);
  });
}
