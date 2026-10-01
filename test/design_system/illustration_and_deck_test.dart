import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/design_system/design_system.dart';
import 'package:oneday_app/design_system/illustration/portrait.dart';

Widget _host(Widget child) => MaterialApp(
  theme: OdTheme.dark(),
  home: Scaffold(body: child),
);

void main() {
  test('activities map to the place they most likely happened', () {
    expect(SceneKind.of('sunrise trek', 0), SceneKind.mountains);
    expect(SceneKind.of('chai at a café', 0), SceneKind.cafe);
    expect(SceneKind.of('rooftop gig', 0), SceneKind.concert);
    expect(SceneKind.of('beach', 0), SceneKind.beach);
    expect(SceneKind.of('cycling in the park', 0), SceneKind.park);
    expect(SceneKind.of(null, 3), SceneKind.values[3]);
  });

  test('a seed always draws the same person', () {
    final a = PortraitLook.fromSeed(42);
    final b = PortraitLook.fromSeed(42);
    expect(a.hairStyle, b.hairStyle);
    expect(a.skin, b.skin);
  });

  testWidgets(
    'every scene and many people paint without errors, tiny and full screen',
    (tester) async {
      for (final size in const [Size(24, 24), Size(390, 844)]) {
        await tester.pumpWidget(
          _host(
            SingleChildScrollView(
              child: Wrap(
                children: [
                  for (final kind in SceneKind.values)
                    SizedBox.fromSize(
                      size: size,
                      child: OdMediaArt(seed: kind.index, scene: kind),
                    ),
                  for (var seed = 0; seed < 40; seed++)
                    SizedBox.fromSize(
                      size: size,
                      child: OdPortrait(seed: seed),
                    ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  group('OdSwipeDeck', () {
    Future<(List<String>, List<(String, bool)>, OdSwipeController)> pumpDeck(
      WidgetTester tester, {
      required bool keepOnRight,
    }) async {
      final items = ['a', 'b', 'c'];
      final decisions = <(String, bool)>[];
      final controller = OdSwipeController();
      await tester.pumpWidget(
        _host(
          Center(
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 360,
                height: 520,
                child: OdSwipeDeck<String>(
                  items: items,
                  itemKey: (s) => s,
                  controller: controller,
                  onDecision: (item, right) async {
                    decisions.add((item, right));
                    if (right && keepOnRight) return false;
                    setState(() => items.remove(item));
                    return true;
                  },
                  builder: (context, item) => ColoredBox(
                    color: Colors.indigo,
                    child: Center(child: Text('card $item')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return (items, decisions, controller);
    }

    testWidgets('a far drag decides, a short one springs back', (tester) async {
      final (items, decisions, _) = await pumpDeck(tester, keepOnRight: false);
      await tester.drag(find.text('card a'), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(decisions, isEmpty);

      await tester.drag(find.text('card a'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(decisions, [('a', false)]);
      expect(items, ['b', 'c']);
      expect(find.text('card b'), findsOneWidget);
    });

    testWidgets('buttons fly the card out through the controller', (
      tester,
    ) async {
      final (items, decisions, controller) = await pumpDeck(
        tester,
        keepOnRight: false,
      );
      controller.swipe(right: true);
      await tester.pumpAndSettle();
      expect(decisions, [('a', true)]);
      expect(items, ['b', 'c']);
    });

    testWidgets('a decision that returns false brings the card back', (
      tester,
    ) async {
      final (items, decisions, controller) = await pumpDeck(
        tester,
        keepOnRight: true,
      );
      final home = tester.getCenter(find.text('card a'));
      controller.swipe(right: true);
      await tester.pumpAndSettle();
      expect(decisions, [('a', true)]);
      expect(items, ['a', 'b', 'c']);
      // Back in place and still swipeable.
      expect(tester.getCenter(find.text('card a')).dx, closeTo(home.dx, 2));
      controller.swipe(right: false);
      await tester.pumpAndSettle();
      expect(items, ['b', 'c']);
    });
  });
}
