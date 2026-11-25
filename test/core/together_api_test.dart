import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/dates.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/token_store.dart';
import 'package:oneday_app/core/plans.dart';
import 'package:oneday_app/core/prompts.dart';
import 'package:oneday_app/core/pulse_status.dart';
import 'package:oneday_app/core/repositories.dart';

import '../support/fake_server.dart';

/// Today's Prompt, Pulse Status, Plans and Date Mode against a scripted server.
void main() {
  late MemoryTokenStore store;

  setUp(() => store = MemoryTokenStore());

  ApiClient client(FakeServer server) => ApiClient(
    baseUrl: 'http://api.test',
    tokens: store,
    dio: Dio()..httpClientAdapter = server,
    retryDelays: const [Duration.zero],
  );

  const plan = {
    'id': 'pl1',
    'title': 'Sunday badminton',
    'activity': 'badminton',
    'hostFirstName': 'Kabir',
    'place': 'Cubbon Park',
    'startsAt': '2026-11-20T12:00:00Z',
    'endsAt': '2026-11-20T14:00:00Z',
    'spotsLeft': 3,
    'status': 'OPEN',
    'yourStatus': 'REQUESTED',
    'going': <String>[],
  };

  const date = {
    'id': 'd1',
    'connectionId': 'c1',
    'partnerFirstName': 'Riya',
    'placeName': 'Third Wave Coffee',
    'startsAt': '2026-11-20T12:00:00Z',
    'endsAt': '2026-11-20T14:00:00Z',
    'status': 'CONFIRMED',
    'youProposed': true,
    'emergencyNumber': '112',
    'partnerSharing': true,
    'you': {'sharingLocation': true, 'trustedContact': 'Meera'},
  };

  test('a prompt answer is a public text story tagged with the prompt', () async {
    final server = FakeServer(
      (o) async => o.method == 'GET'
          ? (
              200,
              {
                'promptKey': 'k1',
                'text': 'What does your street smell like at 7 am?',
                'answeredByYou': false,
                'unlocked': false,
                'answeredNearby': 'A few people nearby answered',
                'answers': <Object>[],
              },
            )
          : (201, {'id': 'm1'}),
    );
    final prompts = ApiPrompts(client(server));

    final today = await prompts.today();
    expect(today.promptKey, 'k1');
    expect(today.answeredByYou, isFalse);

    await prompts.answer(today.promptKey, '  Filter coffee  ');
    expect(server.requests.last.path, '/moments');
    expect(server.requests.last.data, {
      'kind': 'TEXT',
      'caption': 'Filter coffee',
      'shareScope': 'PUBLIC_DISCOVERY',
      'promptKey': 'k1',
    });
  });

  test('Pulse Status sends the mood with its emoji, and no status reads as none', () async {
    final server = FakeServer(
      (o) async => switch ((o.method, o.path)) {
        ('GET', '/pulse-status/mine') => (204, null),
        ('GET', '/pulse-status/friends') => (
          200,
          [
            {
              'connectionId': 'c1',
              'statusId': 'ps1',
              'firstName': 'Arjun',
              'mood': 'LOW',
              'moodLabel': 'Feeling low',
              'emoji': '🌧️',
              'checkIn': true,
            },
          ],
        ),
        _ => (200, {'mood': 'CHILL'}),
      },
    );
    final pulse = ApiPulse(client(server));

    expect(await pulse.mine(), isNull);
    await pulse.set(Mood.chill, note: ' Slow Sunday ');
    expect(server.requests.last.method, 'PUT');
    expect(server.requests.last.data, {
      'mood': 'CHILL',
      'emoji': '😌',
      'note': 'Slow Sunday',
    });
    final friend = (await pulse.friends()).single;
    expect(friend.firstName, 'Arjun');
    expect(friend.checkIn, isTrue);
    await pulse.clear();
    expect(server.requests.last.method, 'DELETE');
    expect(server.requests.last.path, '/pulse-status');
  });

  test(
    'plans: joining asks the host, the Room reads oldest first, and nearby needs the area',
    () async {
      var located = false;
      final server = FakeServer(
        (o) async => switch ((o.method, o.path)) {
          ('GET', '/plans') =>
            located
                ? (200, [plan])
                : (
                    409,
                    {'code': 'LOCATION_REQUIRED', 'detail': 'Share your area'},
                  ),
          ('GET', '/plans/pl1/room') => (
            200,
            [
              {
                'id': 'r2',
                'firstName': 'Kabir',
                'body': 'See you at 5',
                'mine': false,
                'sentAt': '2026-11-20T10:05:00Z',
              },
              {
                'id': 'r1',
                'firstName': 'You',
                'body': 'Hello!',
                'mine': true,
                'sentAt': '2026-11-20T10:00:00Z',
              },
            ],
          ),
          ('POST', '/plans/pl1/room') => (
            422,
            {'code': 'EMPATHY_CHECK', 'detail': 'This might land badly.'},
          ),
          _ => (200, plan),
        },
      );
      final plans = ApiPlans(client(server));

      await expectLater(plans.nearby(), throwsA(isA<LocationRequired>()));
      located = true;
      expect((await plans.nearby()).single.host, 'Kabir');

      final joined = await plans.join('pl1');
      expect(server.requests.last.method, 'POST');
      expect(server.requests.last.path, '/plans/pl1/join');
      expect(joined.asked, isTrue);
      expect(joined.member, isFalse);

      expect([for (final m in await plans.room('pl1')) m.id], ['r1', 'r2']);
      await expectLater(
        plans.say('pl1', 'rude'),
        throwsA(isA<EmpathyCheck>()),
      );

      await plans.decide('pl1', 'h7', approve: true);
      expect(server.requests.last.path, '/plans/pl1/requests/h7/approve');

      await plans.host(
        meetingPointId: 'mp1',
        activity: ' chai ',
        startsAt: DateTime.utc(2026, 11, 20, 12),
        endsAt: DateTime.utc(2026, 11, 20, 14),
        capacity: 4,
      );
      expect(server.requests.last.data, {
        'meetingPointId': 'mp1',
        'activity': 'chai',
        'capacity': 4,
        'startsAt': '2026-11-20T12:00:00.000Z',
        'endsAt': '2026-11-20T14:00:00.000Z',
      });
    },
  );

  test('dates: proposing, sharing, the trusted contact, SOS and the debrief', () async {
    final server = FakeServer(
      (o) async => switch (o.path) {
        '/dates/d1/trusted-contact' => (200, {'name': 'Meera', 'texted': true}),
        '/dates/d1/sos' || '/dates/d1/check-in' => (
          200,
          {
            'message': 'Our safety team has been alerted.',
            'emergencyNumber': '112',
            'trustedContactAlerted': true,
          },
        ),
        '/dates/d1/debrief' => (200, {'message': 'Thanks for telling us.'}),
        _ => (200, date),
      },
    );
    final dates = ApiDates(client(server));

    final proposed = await dates.propose(
      connectionId: 'c1',
      placeName: ' Third Wave Coffee ',
      startsAt: DateTime.utc(2026, 11, 20, 12),
      endsAt: DateTime.utc(2026, 11, 20, 14),
    );
    expect(server.requests.last.data, {
      'connectionId': 'c1',
      'placeName': 'Third Wave Coffee',
      'startsAt': '2026-11-20T12:00:00.000Z',
      'endsAt': '2026-11-20T14:00:00.000Z',
    });
    expect(proposed.partner, 'Riya');
    expect(proposed.confirmed, isTrue);
    expect(proposed.sharing, isTrue);
    expect(proposed.trustedContact, 'Meera');

    await dates.setSharing('d1', enabled: false);
    expect(server.requests.last.method, 'PUT');
    expect(server.requests.last.data, {'enabled': false});

    expect(
      await dates.setTrustedContact('d1', phone: ' 98765 43210 ', name: 'Meera'),
      isTrue,
    );
    expect(server.requests.last.data, {'phone': '98765 43210', 'name': 'Meera'});

    final reply = await dates.sos('d1');
    expect(server.requests.last.path, '/dates/d1/sos');
    expect(reply.contactAlerted, isTrue);
    expect(reply.emergencyNumber, '112');

    await dates.checkIn('d1');
    expect(server.requests.last.data, {'needHelp': false});

    final said = await dates.debrief('d1', {
      DebriefAnswer.goodTime,
      DebriefAnswer.feltSafe,
    });
    expect(said, 'Thanks for telling us.');
    expect(server.requests.last.data, {
      'answers': ['HAD_A_GOOD_TIME', 'FELT_SAFE'],
    });
  });

  test('times read naturally', () {
    final now = DateTime(2026, 11, 17, 9);
    expect(whenLabel(DateTime(2026, 11, 17, 19, 30), now), 'Today 7:30 pm');
    expect(whenLabel(DateTime(2026, 11, 18, 0, 5), now), 'Tomorrow 12:05 am');
    expect(whenLabel(DateTime(2026, 11, 21, 12), now), 'Sat 21 Nov, 12:00 pm');
  });
}
