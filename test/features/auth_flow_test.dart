import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/app.dart';
import 'package:oneday_app/core/auth/auth_repository.dart';
import 'package:oneday_app/core/fake_repositories.dart';
import 'package:oneday_app/core/providers.dart';
import 'package:oneday_app/design_system/design_system.dart';
import 'package:oneday_app/features/auth/about_you_screen.dart';

Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget app(FakeAuthRepository auth) => ProviderScope(
  overrides: [
    dataProvider.overrideWithValue(
      FakeData(latency: const Duration(milliseconds: 10)),
    ),
    authRepositoryProvider.overrideWithValue(auth),
  ],
  child: const OneDayApp(),
);

void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> enterDob(WidgetTester tester, String mmddyyyy) async {
  await tester.tap(find.bySemanticsLabel(RegExp('date of birth')));
  await settle(tester);
  await tester.enterText(
    find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
    mmddyyyy,
  );
  await tester.tap(find.text('OK'));
  await settle(tester);
}

void main() {
  group('authRedirect', () {
    test('waits on a splash while the session is read', () {
      expect(authRedirect(AuthState.unknown, '/chats'), '/splash');
      expect(authRedirect(AuthState.unknown, '/splash'), isNull);
    });
    test('signed out: anything outside sign-in goes to welcome', () {
      expect(authRedirect(AuthState.signedOut, '/'), '/welcome');
      expect(authRedirect(AuthState.signedOut, '/splash'), '/welcome');
      expect(authRedirect(AuthState.signedOut, '/auth/otp'), isNull);
    });
    test('signed in: sign-in screens go home, deep links are kept', () {
      const inside = AuthState(AuthStage.signedIn);
      expect(authRedirect(inside, '/welcome'), '/');
      expect(authRedirect(inside, '/auth/phone'), '/');
      expect(authRedirect(inside, '/chats'), isNull);
    });
  });

  testWidgets(
    'a new phone number signs up in three steps and lands on the camera',
    (tester) async {
      phoneSize(tester);
      await tester.pumpWidget(app(FakeAuthRepository(latency: Duration.zero)));
      await settle(tester);
      expect(find.text('Continue with phone'), findsOneWidget);

      await tester.tap(find.text('Continue with phone'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('phone-field')),
        '9876543210',
      );
      await tester.pump();
      await tester.tap(find.text('Send code'));
      await settle(tester);
      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.textContaining('+91 98765 43210'), findsOneWidget);

      // A wrong code clears the boxes and says so, without leaving the screen.
      await tester.enterText(find.byKey(const Key('otp-field')), '000000');
      await settle(tester);
      expect(find.text('That code isn\'t right'), findsOneWidget);

      // The sixth digit submits by itself; a new number is asked for details.
      await tester.enterText(find.byKey(const Key('otp-field')), '123456');
      await settle(tester);
      expect(find.text('A little about you'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('name-field')), 'Asha');
      await enterDob(tester, '04/09/1999');
      await tester.tap(find.byKey(const Key('consent')));
      await tester.pump();
      await tester.tap(find.text('Start OneDay'));
      await settle(tester);
      expect(find.bySemanticsLabel(RegExp('Shutter')), findsOneWidget);
    },
  );

  testWidgets(
    'email sign-in goes straight in; a session ended by the server returns to welcome',
    (tester) async {
      phoneSize(tester);
      final auth = FakeAuthRepository(latency: Duration.zero);
      await tester.pumpWidget(app(auth));
      await settle(tester);
      await tester.tap(find.text('Use email instead'));
      await settle(tester);
      expect(find.text('Welcome back'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('email-field')),
        'asha@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('password-field')),
        'a long enough passphrase',
      );
      await tester.pump();
      await tester.tap(find.text('Sign in'));
      await settle(tester);
      expect(find.bySemanticsLabel(RegExp('Shutter')), findsOneWidget);

      auth.endSession();
      await settle(tester);
      expect(find.text('Continue with phone'), findsOneWidget);
    },
  );

  testWidgets('under-18s are told why and cannot continue', (tester) async {
    phoneSize(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(latency: Duration.zero),
          ),
        ],
        child: MaterialApp(
          theme: OdTheme.dark(),
          home: AboutYouScreen(
            args: const AboutYouArgs.email(
              email: 'a@b.co',
              password: 'twelve chars!',
            ),
            today: DateTime(2026, 10, 1),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.enterText(find.byKey(const Key('name-field')), 'Kid');
    await enterDob(tester, '10/02/2008'); // one day short of 18
    await tester.tap(find.byKey(const Key('consent')));
    await tester.pump();
    expect(find.text('OneDay is only for adults 18 and over.'), findsOneWidget);
    final button = tester.widget<OdButton>(
      find.widgetWithText(OdButton, 'Start OneDay'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('sign-in screens survive a small phone at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app(FakeAuthRepository(latency: Duration.zero)));
    await settle(tester);
    await tester.tap(find.text('Continue with phone'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('phone-field')), '9876543210');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(find.text('Enter the code'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await settle(tester);
    // The focused name field scrolls into view; the action stays pinned above it.
    expect(
      find.text('A little about you', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Start OneDay'), findsOneWidget);
  });
}
