import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/api_repositories.dart';
import 'package:oneday_app/core/models.dart';
import 'package:oneday_app/core/providers.dart';
import 'package:oneday_app/core/repositories.dart';
import 'package:oneday_app/design_system/design_system.dart';
import 'package:oneday_app/features/camera/camera_screen.dart';

/// Records what the preview asks the story repository to do, and can fail the next publish once.
class _Stories implements StoryRepository {
  final drafts = <StoryDraft>[];
  Object? failNext;

  @override
  Future<List<Story>> friendsStories() async => const [];

  @override
  Future<String> upload(Capture capture) async => 'ref-1';

  @override
  Future<void> publish(StoryDraft draft) async {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    drafts.add(draft);
  }
}

Future<void> _openPreview(
  WidgetTester tester,
  _Stories stories,
  ShareScope scope,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storyRepositoryProvider.overrideWithValue(stories),
        locationShareProvider.overrideWithValue(FakeLocationShare()),
      ],
      child: MaterialApp(
        theme: OdTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CapturePreview(seed: 1, video: false, scope: scope),
                  ),
                ),
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

/// Pumps frames without waiting for endless animations to settle.
Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'sharing publishes the caption and activity to friends and closes the preview',
    (tester) async {
      final stories = _Stories();
      await _openPreview(tester, stories, ShareScope.friends);

      await tester.enterText(find.byType(TextField), 'Filter coffee');
      await tester.tap(find.text('Trek'));
      await tester.pump();
      await tester.tap(find.text('Share with friends'));
      await _settle(tester);

      final draft = stories.drafts.single;
      expect(draft.scope, ShareScope.friends);
      expect(draft.caption, 'Filter coffee');
      expect(draft.activity, 'trek');
      expect(draft.mediaRef, isNull);
      expect(find.byType(CapturePreview), findsNothing);
      expect(find.text('Shared. It disappears in 24 hours.'), findsOneWidget);
    },
  );

  testWidgets(
    'a nearby share asks for the area first, then goes out after "Share my area"',
    (tester) async {
      final stories = _Stories()..failNext = const LocationRequired();
      await _openPreview(tester, stories, ShareScope.nearby);

      await tester.enterText(find.byType(TextField), 'Sunrise at Nandi Hills');
      await tester.tap(find.text('Share nearby'));
      await _settle(tester, 4);
      expect(stories.drafts, isEmpty);
      expect(find.byType(CapturePreview), findsOneWidget);

      await tester.tap(find.text('Share my area'));
      await _settle(tester);
      expect(stories.drafts.single.scope, ShareScope.nearby);
      expect(find.byType(CapturePreview), findsNothing);
    },
  );

  testWidgets('a story with no words and no photo says what is missing', (
    tester,
  ) async {
    final stories = _Stories()..failNext = const CaptionRequired();
    await _openPreview(tester, stories, ShareScope.friends);

    await tester.tap(find.text('Share with friends'));
    await _settle(tester, 4);

    expect(find.text('Add a few words to share this.'), findsOneWidget);
    expect(find.byType(CapturePreview), findsOneWidget);
  });
}
