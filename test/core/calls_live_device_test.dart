import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/calls.dart';
import 'package:oneday_app/core/dates.dart';
import 'package:oneday_app/core/device.dart';
import 'package:oneday_app/core/live.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/token_store.dart';

import '../support/fake_server.dart';

class _Token implements PushTokenSource {
  _Token(this.value);

  final String? value;

  @override
  Future<String?> token() async => value;
}

/// Calls, Circle Live, Date Mode position and push registration against a scripted server.
void main() {
  late MemoryTokenStore store;

  setUp(() => store = MemoryTokenStore());

  ApiClient client(FakeServer server) => ApiClient(
    baseUrl: 'http://api.test',
    tokens: store,
    dio: Dio()..httpClientAdapter = server,
    retryDelays: const [Duration.zero],
  );

  const call = {
    'id': 'k1',
    'connectionId': 'c1',
    'firstName': 'Riya',
    'direction': 'INCOMING',
    'status': 'ACTIVE',
    'layer': 'VOICE',
    'youWant': 'BLURRED',
    'theyAreReadyForMore': false,
  };

  test('calls: layers, signalling and ICE servers in the shapes WebRTC and the server expect', () async {
    final server = FakeServer(
      (o) async => o.path == '/calls/ice-servers'
          ? (
              200,
              {
                'expiresAt': 1763460000,
                'iceServers': [
                  {'urls': ['stun:stun.example:3478']},
                  {
                    'urls': ['turn:turn.example:3478'],
                    'username': '1763460000:u1',
                    'credential': 'secret',
                  },
                ],
              },
            )
          : (200, call),
    );
    final calls = CallsApi(client(server));

    final state = await calls.want('k1', CallLayer.blurred);
    expect(server.requests.last.method, 'PUT');
    expect(server.requests.last.data, {'wants': 'BLURRED'});
    expect(state.incoming, isTrue);
    expect(state.active, isTrue);
    expect(state.layer, CallLayer.voice, reason: 'the call runs at the lower choice');
    expect(state.youWant, CallLayer.blurred);

    await calls.signal('k1', CallSignal('OFFER', jsonEncode({'sdp': 'v=0', 'type': 'offer'})));
    expect(server.requests.last.path, '/calls/k1/signal');
    expect((server.requests.last.data as Map)['kind'], 'OFFER');

    final ice = await calls.iceServers();
    expect(ice['iceServers'], [
      {'urls': ['stun:stun.example:3478']},
      {'urls': ['turn:turn.example:3478'], 'username': '1763460000:u1', 'credential': 'secret'},
    ]);
  });

  test('Circle Live: going live to connections, and a viewer\'s access', () async {
    final server = FakeServer(
      (o) async => (
        o.path == '/live' ? 201 : 200,
        {
          'live': {'id': 'l1', 'hostFirstName': 'Zoya', 'state': 'LIVE', 'title': 'Soundcheck'},
          'access': {
            'serverUrl': 'wss://live.example',
            'token': 'jwt',
            'expiresAt': '2026-11-18T10:10:00Z',
          },
          if (o.path == '/live') 'viewers': 0,
        },
      ),
    );
    final live = ApiLive(client(server));

    final hosting = await live.start(title: ' Soundcheck ');
    expect(server.requests.last.data, {'title': 'Soundcheck'});
    expect(hosting.viewers, 0);
    expect(hosting.access.serverUrl, 'wss://live.example');

    final watching = await live.join('l1');
    expect(server.requests.last.path, '/live/l1/join');
    expect(watching.session.live, isTrue);
    expect(watching.viewers, isNull, reason: 'viewers never see the count');
    expect(watching.access.expiresAt, isNotNull);
  });

  test('Date Mode sends the position, and reads the partner\'s', () async {
    final server = FakeServer(
      (o) async => (
        200,
        {
          'id': 'd1',
          'connectionId': 'c1',
          'partnerFirstName': 'Riya',
          'placeName': 'Third Wave Coffee',
          'startsAt': '2026-11-18T10:00:00Z',
          'endsAt': '2026-11-18T12:00:00Z',
          'status': 'CONFIRMED',
          'locationWindowOpen': true,
          'partnerSharing': true,
          'partnerLocation': {'lat': 12.9345, 'lon': 77.626, 'at': '2026-11-18T10:05:00Z'},
          'you': {'sharingLocation': true},
        },
      ),
    );
    final date = await ApiDates(client(server)).sendPosition('d1', 12.9352, 77.6245);
    expect(server.requests.single.method, 'PUT');
    expect(server.requests.single.path, '/dates/d1/location');
    expect(server.requests.single.data, {'lat': 12.9352, 'lon': 77.6245});
    expect(date.shouldSend, isTrue);
    expect(date.partnerLat, 12.9345);
    expect(date.partnerAt, isNotNull);
  });

  test('push registers a token once, unregisters it, and does nothing without one', () async {
    final server = FakeServer((o) async => (201, {'platform': 'ANDROID'}));
    final push = PushRegistration(client(server), _Token('fcm-1'), platform: 'ANDROID');

    await push.register();
    await push.register();
    expect(server.requests, hasLength(1));
    expect(server.requests.single.data, {'pushToken': 'fcm-1', 'platform': 'ANDROID'});

    await push.unregister();
    expect(server.requests.last.path, '/devices/unregister');
    expect(server.requests.last.data, {'pushToken': 'fcm-1'});

    final none = FakeServer((o) async => (201, null));
    await PushRegistration(client(none), _Token(null), platform: 'ANDROID').register();
    expect(none.requests, isEmpty);
  });
}
