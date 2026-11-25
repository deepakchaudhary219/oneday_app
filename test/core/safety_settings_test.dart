import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/api_repositories.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/token_store.dart';
import 'package:oneday_app/core/repositories.dart';
import 'package:oneday_app/core/safety.dart';
import 'package:oneday_app/core/settings.dart';
import 'package:oneday_app/core/story_map.dart';

import '../support/fake_server.dart';

/// Safety, settings, the Story Map and Investment Balance against a scripted server: request shapes, JSON
/// mapping and error-code translation.
void main() {
  late MemoryTokenStore store;

  setUp(() => store = MemoryTokenStore());

  ApiClient client(FakeServer server) => ApiClient(
    baseUrl: 'http://api.test',
    tokens: store,
    dio: Dio()..httpClientAdapter = server,
    retryDelays: const [Duration.zero],
  );

  test(
    'a block and a report name exactly one target, and a report can block too',
    () async {
      final server = FakeServer(
        (o) async => o.path == '/safety/reports'
            ? (
                201,
                {
                  'reportId': 'r1',
                  'status': 'OPEN',
                  'message': 'Thanks. We look at these within 24 hours.',
                },
              )
            : (200, null),
      );
      final safety = ApiSafety(client(server));

      await safety.block(const SafetyTarget.moment('m1'));
      expect(server.requests.last.path, '/safety/blocks');
      expect(server.requests.last.data, {'momentId': 'm1'});

      final said = await safety.report(
        const SafetyTarget.connection('c1'),
        ReportCategory.harassment,
        details: '  Kept messaging  ',
        alsoBlock: true,
      );
      expect(said, contains('24 hours'));
      expect(server.requests.last.data, {
        'connectionId': 'c1',
        'category': 'HARASSMENT',
        'details': 'Kept messaging',
        'alsoBlock': true,
      });

      await safety.leaveQuietly('c1');
      expect(server.requests.last.method, 'POST');
      expect(server.requests.last.path, '/connections/c1/exit');
    },
  );

  test('settings send only what changed and read the profile back', () async {
    final server = FakeServer(
      (o) async => (
        200,
        {
          'discoveryRadiusKm': 12,
          'datingLens': true,
          'discretionMode': false,
          'accountPrivacy': 'PRIVATE',
          'emergencyNumber': '112',
        },
      ),
    );
    final prefs = await ApiSettings(
      client(server),
    ).update(discoveryRadiusKm: 12, privateAccount: true);
    final sent = server.requests.single;
    expect(sent.method, 'PATCH');
    expect(sent.path, '/profile/me');
    expect(sent.data, {'discoveryRadiusKm': 12, 'accountPrivacy': 'PRIVATE'});
    expect(prefs.discoveryRadiusKm, 12);
    expect(prefs.privateAccount, isTrue);
    expect(prefs.datingLens, isTrue);
    expect(prefs.emergencyNumber, '112');
  });

  test(
    'withdrawing consent deletes the purpose; deleting the account confirms explicitly',
    () async {
      final server = FakeServer(
        (o) async => o.path.startsWith('/consents')
            ? (
                200,
                [
                  {
                    'purpose': 'LOCATION_DISCOVERY',
                    'processes': 'Your area while the app is open',
                    'onWithdrawal': 'Your area is deleted',
                    'state': 'WITHDRAWN',
                  },
                ],
              )
            : (200, null),
      );
      final settings = ApiSettings(client(server));

      final purposes = await settings.withdraw('LOCATION_DISCOVERY');
      expect(server.requests.last.method, 'DELETE');
      expect(server.requests.last.path, '/consents/LOCATION_DISCOVERY');
      expect(purposes.single.granted, isFalse);
      expect(purposes.single.title, 'Location for Nearby');

      await settings.deleteAccount();
      expect(server.requests.last.method, 'DELETE');
      expect(server.requests.last.path, '/privacy/account');
      expect(server.requests.last.uri.queryParameters['confirm'], 'DELETE');
    },
  );

  test('the map asks through one lens, and needs the area first', () async {
    final server = FakeServer((o) async {
      if (o.uri.queryParameters['scope'] == 'ROOTS') {
        return (
          409,
          {'code': 'LOCATION_REQUIRED', 'detail': 'Share your location first'},
        );
      }
      return (
        200,
        {
          'scope': 'RADIUS',
          'clusters': [
            {
              'id': 'k1',
              'vibe': 'Street food evening',
              'centerLat': 12.93,
              'centerLon': 77.62,
              'liveNow': true,
              'more': 4,
              'activities': ['street food'],
              'stories': [
                {
                  'momentId': 'm1',
                  'firstName': 'Riya',
                  'activity': 'street food',
                },
              ],
            },
          ],
        },
      );
    });
    final map = ApiMap(client(server));

    final data = await map.stories(MapLens.prompt);
    expect(server.requests.single.path, '/map/stories');
    expect(server.requests.single.uri.queryParameters, {
      'scope': 'RADIUS',
      'todaysPrompt': 'true',
    });
    final area = data.areas.single;
    expect(area.name, 'Street food evening');
    expect(area.count, 5);
    expect(area.busy, isTrue);
    expect(area.stories.single.firstName, 'Riya');

    await expectLater(
      map.stories(MapLens.roots),
      throwsA(isA<LocationRequired>()),
    );
  });

  test('Investment Balance speaks only when there is a nudge', () async {
    var state = 'BALANCED';
    final server = FakeServer(
      (o) async => (200, {'state': state, 'message': 'Maybe ask them back?'}),
    );
    final chat = ApiData(client(server));
    expect(await chat.balanceNudge('c1'), isNull);
    expect(server.requests.single.path, '/conversations/c1/balance');
    state = 'NUDGE';
    expect(await chat.balanceNudge('c1'), 'Maybe ask them back?');
  });
}
