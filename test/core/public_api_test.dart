import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/amas.dart';
import 'package:oneday_app/core/figures.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/token_store.dart';
import 'package:oneday_app/core/relays.dart';
import 'package:oneday_app/core/repositories.dart';

import '../support/fake_server.dart';

/// Story Relays, Spotlights, Public Figures and AMAs against a scripted server.
void main() {
  late MemoryTokenStore store;

  setUp(() => store = MemoryTokenStore());

  ApiClient client(FakeServer server) => ApiClient(
    baseUrl: 'http://api.test',
    tokens: store,
    dio: Dio()..httpClientAdapter = server,
    retryDelays: const [Duration.zero],
  );

  test('a relay answer is a public text story that replies to the moment', () async {
    var located = false;
    final server = FakeServer(
      (o) async => switch ((o.method, o.path)) {
        ('GET', '/moments/m1/relay') => (
          200,
          {
            'relayId': 'm1',
            'activity': 'sunrise',
            'open': true,
            'links': [
              {'momentId': 'm1', 'firstName': 'Ananya', 'position': 0, 'mine': true},
              {'momentId': 'm2', 'firstName': 'Kabir', 'position': 1, 'spotlit': true},
            ],
          },
        ),
        ('POST', '/moments') when !located => (
          409,
          {'code': 'LOCATION_REQUIRED', 'detail': 'Share your area'},
        ),
        _ => (201, {'id': 'x'}),
      },
    );
    final relays = ApiRelays(client(server));

    final relay = await relays.relay('m1');
    expect(relay.root!.mine, isTrue);
    expect(relay.links.last.spotlit, isTrue);

    await expectLater(
      relays.answer('m2', 'Me too'),
      throwsA(isA<LocationRequired>()),
    );
    located = true;
    await relays.answer('m2', '  Me too  ');
    expect(server.requests.last.data, {
      'kind': 'TEXT',
      'caption': 'Me too',
      'shareScope': 'PUBLIC_DISCOVERY',
      'replyToMomentId': 'm2',
    });

    await relays.proposeSpotlight('m1', 'm2');
    expect(server.requests.last.path, '/moments/m1/spotlights');
    expect(server.requests.last.data, {'answerMomentId': 'm2'});
    await relays.decideSpotlight('sp1', accept: false);
    expect(server.requests.last.path, '/spotlights/sp1/decline');
  });

  test('figures: handles are normalised, an unknown one reads as not found, applying sends the category', () async {
    final server = FakeServer(
      (o) async => switch ((o.method, o.path)) {
        ('GET', '/figures/nobody') => (404, {'code': 'NOT_FOUND', 'detail': 'Not found'}),
        ('GET', '/figures/me') => (204, null),
        ('POST', '/figures/apply') => (
          201,
          {'handle': 'riya.sings', 'publicName': 'Riya', 'status': 'PENDING'},
        ),
        _ => (
          200,
          {
            'handle': 'riya.sings',
            'publicName': 'Riya',
            'category': 'MUSICIAN',
            'verified': true,
            'following': true,
          },
        ),
      },
    );
    final figures = ApiFigures(client(server));

    final figure = await figures.follow(' @Riya.Sings ');
    expect(server.requests.last.path, '/figures/riya.sings/follow');
    expect(figure.category, FigureCategory.musician);
    expect(figure.following, isTrue);

    await expectLater(figures.figure('nobody'), throwsA(isA<FigureNotFound>()));
    expect(await figures.mine(), isNull);

    final applied = await figures.apply(
      handle: 'Riya.Sings',
      publicName: ' Riya ',
      category: FigureCategory.musician,
      evidence: ' https://example.com/riya ',
    );
    expect(server.requests.last.data, {
      'handle': 'riya.sings',
      'publicName': 'Riya',
      'category': 'MUSICIAN',
      'evidence': 'https://example.com/riya',
    });
    expect(applied.approved, isFalse);
  });

  test('AMAs: asking can be anonymous, the Empathy Mirror can pause it, votes go on and off', () async {
    final server = FakeServer(
      (o) async => switch ((o.method, o.path)) {
        ('GET', '/amas/a1') => (
          200,
          {
            'ama': {
              'id': 'a1',
              'title': 'Growing up in Kochi',
              'hostName': 'Ranveer',
              'startsAt': '2026-11-18T10:00:00Z',
              'endsAt': '2026-11-18T11:00:00Z',
              'state': 'LIVE',
              'corridorRegion': 'IN-KL',
              'canAsk': true,
            },
            'questions': [
              {'id': 'q1', 'question': 'Favourite dish?', 'askedBy': 'Someone from IN-KL'},
            ],
          },
        ),
        ('POST', '/amas/a1/questions') => (
          422,
          {'code': 'EMPATHY_CHECK', 'detail': 'This might land badly.'},
        ),
        ('POST', '/amas') => (
          201,
          {
            'id': 'a2',
            'title': 'Onam special',
            'hostName': 'You',
            'startsAt': '2026-11-20T10:00:00Z',
            'endsAt': '2026-11-20T11:00:00Z',
            'state': 'UPCOMING',
            'youHost': true,
          },
        ),
        _ => (200, null),
      },
    );
    final amas = ApiAmas(client(server));

    final detail = await amas.detail('a1');
    expect(detail.ama.live, isTrue);
    expect(detail.ama.corridorRegion, 'IN-KL');
    expect(detail.questions.single.votes, isNull);

    await expectLater(
      amas.ask('a1', 'rude', anonymous: true),
      throwsA(isA<EmpathyCheck>()),
    );
    expect(server.requests.last.data, {
      'question': 'rude',
      'anonymous': true,
      'sendAnyway': false,
    });

    await amas.vote('a1', 'q1', on: true);
    expect(server.requests.last.method, 'POST');
    await amas.vote('a1', 'q1', on: false);
    expect(server.requests.last.method, 'DELETE');
    expect(server.requests.last.path, '/amas/a1/questions/q1/vote');

    final hosted = await amas.schedule(
      title: ' Onam special ',
      startsAt: DateTime.utc(2026, 11, 20, 10),
      corridorRegion: ' in-kl ',
    );
    expect(server.requests.last.data, {
      'title': 'Onam special',
      'startsAt': '2026-11-20T10:00:00.000Z',
      'minutes': 60,
      'corridorRegion': 'IN-KL',
    });
    expect(hosted.youHost, isTrue);
  });
}
