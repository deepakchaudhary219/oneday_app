import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/capsules.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/token_store.dart';
import 'package:oneday_app/core/plus_ledger.dart';
import 'package:oneday_app/core/repositories.dart';
import 'package:oneday_app/core/right_now.dart';
import 'package:oneday_app/core/threads.dart';

import '../support/fake_server.dart';

/// Right Now, Time Capsules, Threads, Plus and the ledger against a scripted server.
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
    'Right Now: off in this city reads as unavailable, none of mine reads as null, start sends the length',
    () async {
      var cityOpen = false;
      final server = FakeServer(
        (o) async => switch ((o.method, o.path)) {
          ('GET', '/right-now') when !cityOpen => (
            404,
            {'code': 'NOT_FOUND', 'detail': 'Right Now not found'},
          ),
          ('GET', '/right-now') => (
            200,
            [
              {
                'id': 's1',
                'firstName': 'Meera',
                'activity': 'badminton',
                'distance': 'Under 1 km',
                'timeLeft': 'for about an hour',
                'youAsked': false,
              },
            ],
          ),
          ('GET', '/right-now/mine') => (204, null),
          ('POST', '/right-now') => (
            201,
            {'activity': 'chai', 'timeLeft': 'for a while yet'},
          ),
          ('POST', '/right-now/requests/rq1/accept') => (
            200,
            {'connectionId': 'c9', 'conversationId': 'v9'},
          ),
          _ => (200, {'message': 'Asked.'}),
        },
      );
      final rightNow = ApiRightNow(client(server));

      await expectLater(
        rightNow.nearby(),
        throwsA(isA<RightNowUnavailable>()),
      );
      cityOpen = true;
      expect((await rightNow.nearby()).single.firstName, 'Meera');
      expect(await rightNow.mine(), isNull);

      final mine = await rightNow.start(' chai ', minutes: 120);
      expect(server.requests.last.data, {'activity': 'chai', 'minutes': 120});
      expect(mine.activity, 'chai');

      expect(await rightNow.join('s1'), 'Asked.');
      expect(server.requests.last.path, '/right-now/s1/join');
      expect(await rightNow.accept('rq1'), 'v9');
    },
  );

  test('a capsule seals for a day, and for yourself it names no connection', () async {
    final server = FakeServer(
      (o) async => (
        201,
        {
          'id': 'cp1',
          'direction': 'SELF',
          'state': 'SEALED',
          'opensAt': '2027-11-18T00:00:00Z',
        },
      ),
    );
    final capsules = ApiCapsules(client(server));

    final sealed = await capsules.seal(
      message: '  Dear future me  ',
      opensAt: DateTime.utc(2027, 11, 18),
    );
    expect(server.requests.single.path, '/capsules');
    expect(server.requests.single.data, {
      'message': 'Dear future me',
      'opensAt': '2027-11-18T00:00:00.000Z',
    });
    expect(sealed.toSelf, isTrue);
    expect(sealed.open, isFalse);

    await capsules.seal(
      message: 'Same time next year?',
      opensAt: DateTime.utc(2027, 11, 18),
      connectionId: 'c1',
    );
    expect(server.requests.last.data['connectionId'], 'c1');
  });

  test(
    'threads: create with invitees, posts read oldest first, a post is words with the Empathy Mirror',
    () async {
      final server = FakeServer(
        (o) async => switch ((o.method, o.path)) {
          ('GET', '/threads/t1/posts') => (
            200,
            [
              {
                'id': 'p2',
                'firstName': 'Zoya',
                'mine': false,
                'postedAt': '2026-11-18T10:05:00Z',
                'caption': 'Sunset!',
              },
              {
                'id': 'p1',
                'firstName': 'Rohan',
                'mine': false,
                'postedAt': '2026-11-18T10:00:00Z',
                'caption': 'Landed',
              },
            ],
          ),
          ('POST', '/threads/t1/posts') => (
            422,
            {'code': 'EMPATHY_CHECK', 'detail': 'This might land badly.'},
          ),
          _ => (
            200,
            {
              'id': 't1',
              'title': 'Goa trip',
              'myStatus': 'IN',
              'open': true,
              'endsAt': '2026-11-21T10:00:00Z',
              'youStartedIt': true,
              'members': [
                {'handle': 'a', 'firstName': 'You', 'you': true},
              ],
            },
          ),
        },
      );
      final threads = ApiThreads(client(server));

      final thread = await threads.create(
        ' Goa trip ',
        days: 4,
        inviteConnectionIds: ['c1', 'c2'],
      );
      expect(server.requests.last.data, {
        'title': 'Goa trip',
        'days': 4,
        'inviteConnectionIds': ['c1', 'c2'],
      });
      expect(thread.invited, isFalse);
      expect(thread.members.single.you, isTrue);

      expect([for (final p in await threads.posts('t1')) p.id], ['p1', 'p2']);
      await expectLater(
        threads.post('t1', 'rude'),
        throwsA(isA<EmpathyCheck>()),
      );
      expect(server.requests.last.data, {
        'kind': 'TEXT',
        'caption': 'rude',
        'sendAnyway': false,
      });
    },
  );

  test('Plus lists what is never sold; the ledger asks for this month by default', () async {
    final server = FakeServer(
      (o) async => switch (o.path) {
        '/plus' => (
          200,
          {
            'plus': false,
            'available': true,
            'price': '₹149 a month',
            'benefits': ['Wider radius'],
            'neverSold': ['Safety features'],
          },
        ),
        '/plus/subscribe' => (
          200,
          {'subscriptionId': 'sub_1', 'checkoutUrl': 'https://rzp.io/x'},
        ),
        '/ledger' => (
          200,
          {
            'month': '2026-11',
            'lines': ['You made 2 new connections.'],
            'newConnections': 2,
          },
        ),
        _ => (200, {'ready': false}),
      },
    );
    final repo = ApiPlusLedger(client(server));

    final plus = await repo.plus();
    expect(plus.plus, isFalse);
    expect(plus.neverSold, ['Safety features']);
    expect((await repo.subscribe()).url, 'https://rzp.io/x');

    final month = await repo.ledger();
    expect(server.requests.last.uri.queryParameters, isEmpty);
    expect(month.newConnections, 2);
    await repo.ledger(month: '2026-10');
    expect(server.requests.last.uri.queryParameters['month'], '2026-10');
    expect((await repo.week()).ready, isFalse);
  });
}
