import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/app.dart';
import 'package:oneday_app/core/fake_repositories.dart';
import 'package:oneday_app/core/providers.dart';
import 'package:oneday_app/features/chats/chat_thread_screen.dart';
import 'package:oneday_app/core/models.dart';
import 'package:oneday_app/design_system/design_system.dart';
import 'package:oneday_app/features/signals/signals_screen.dart';
import 'package:oneday_app/features/stories/story_viewer.dart';

Widget _app(Widget child) => ProviderScope(
  overrides: [
    dataProvider.overrideWithValue(
      FakeData(latency: const Duration(milliseconds: 10)),
    ),
  ],
  child: MaterialApp(theme: OdTheme.dark(), home: child),
);

/// Pumps frames without waiting for endless animations (shimmer, story progress) to settle.
Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'the app opens on the camera and the bar moves between surfaces',
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataProvider.overrideWithValue(
              FakeData(latency: const Duration(milliseconds: 10)),
            ),
          ],
          child: const OneDayApp(),
        ),
      );
      await settle(tester);
      expect(find.bySemanticsLabel(RegExp('Shutter')), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Chats'));
      await settle(tester);
      expect(find.text('Riya'), findsWidgets);
      expect(find.text('3 people reached out'), findsOneWidget);
      addTearDown(tester.view.reset);
    },
  );

  testWidgets('nearby is bounded: it ends with a closure card', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataProvider.overrideWithValue(
            FakeData(latency: const Duration(milliseconds: 10)),
          ),
        ],
        child: const OneDayApp(),
      ),
    );
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Nearby'));
    await settle(tester);
    for (var i = 0; i < 5; i++) {
      await tester.fling(
        find.byType(PageView).last,
        const Offset(0, -600),
        2000,
      );
      await settle(tester, 15);
    }
    expect(find.text('That\'s everyone nearby for now'), findsOneWidget);
    addTearDown(tester.view.reset);
  });

  testWidgets('swiping a signal card right reveals; the button lets one pass', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(_app(const SignalsScreen()));
    await settle(tester);
    expect(find.text('3 people reached out'), findsOneWidget);

    await tester.drag(find.textContaining('Ananya:'), const Offset(300, 0));
    await settle(tester);
    expect(find.text('You and Ananya are connected'), findsOneWidget);
    await tester.tap(find.text('Say hi'));
    await settle(tester);
    expect(find.text('2 people reached out'), findsOneWidget);

    await tester.tap(find.text('Let it pass'));
    await settle(tester);
    expect(find.text('1 person reached out'), findsOneWidget);
    addTearDown(tester.view.reset);
  });

  testWidgets('a small drag springs back without deciding', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(_app(const SignalsScreen()));
    await settle(tester);
    await tester.drag(find.textContaining('Ananya:'), const Offset(40, 0));
    await settle(tester);
    expect(find.text('3 people reached out'), findsOneWidget);
    addTearDown(tester.view.reset);
  });

  testWidgets(
    'the Empathy Mirror offers edit or send anyway, and nothing is lost',
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      const conv = Conversation(
        id: 'c1',
        firstName: 'Riya',
        lastMessage: '',
        when: 'now',
        warmth: 2,
        seed: 1,
      );
      await tester.pumpWidget(_app(const ChatThreadScreen(conversation: conv)));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'you are so stupid');
      await tester.pump(); // the send button enables on the next frame, as it would for a person
      await tester.tap(find.bySemanticsLabel('Send'));
      await settle(tester);
      expect(find.text('A moment to reflect'), findsOneWidget);

      await tester.tap(find.text('Edit message'));
      await settle(tester);
      expect(
        find.text('you are so stupid'),
        findsOneWidget,
      ); // back in the composer

      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await settle(tester);
      await tester.tap(find.text('Send anyway'));
      await settle(tester);
      expect(
        find.text('you are so stupid'),
        findsOneWidget,
      ); // now a sent bubble
      expect(find.text('A moment to reflect'), findsNothing);
      addTearDown(tester.view.reset);
    },
  );

  testWidgets('stories advance on tap and close on swipe down', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    const stories = [
      Story(
        id: 'a',
        firstName: 'Riya',
        seed: 1,
        frames: [
          StoryFrame(seed: 1, postedAgo: '1m', caption: 'First'),
          StoryFrame(seed: 2, postedAgo: '1m', caption: 'Second'),
        ],
      ),
    ];
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => openStory(context, stories, 0),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester, 10);
    expect(find.text('First'), findsOneWidget);
    await tester.tapAt(const Offset(350, 400));
    await settle(tester, 10);
    expect(find.text('Second'), findsOneWidget);
    await tester.drag(find.text('Second'), const Offset(0, 400));
    await settle(tester, 10);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Second'), findsNothing);
    addTearDown(tester.view.reset);
  });

  testWidgets(
    'surfaces lay out on a small phone at 200% text without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1136); // 320 x 568 dp
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dataProvider.overrideWithValue(
              FakeData(latency: const Duration(milliseconds: 10)),
            ),
          ],
          child: const OneDayApp(),
        ),
      );
      await settle(tester);
      for (final tab in ['Map', 'Chats', 'Nearby', 'Me']) {
        await tester.tap(find.bySemanticsLabel(tab));
        await settle(tester);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
