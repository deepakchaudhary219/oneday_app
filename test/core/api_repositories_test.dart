import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/api_repositories.dart';
import 'package:oneday_app/core/auth/auth_repository.dart';
import 'package:oneday_app/core/models.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/api_error.dart';
import 'package:oneday_app/core/network/token_store.dart';
import 'package:oneday_app/core/repositories.dart';

import '../support/fake_server.dart';

/// The API repositories against a scripted server: request shapes, JSON mapping and error-code translation.
void main() {
  final now = DateTime.utc(2026, 10, 1, 12);
  late MemoryTokenStore store;

  setUp(() => store = MemoryTokenStore());

  ApiClient client(FakeServer server) => ApiClient(
    baseUrl: 'http://api.test',
    tokens: store,
    dio: Dio()..httpClientAdapter = server,
    uploader: Dio()..httpClientAdapter = server,
    retryDelays: const [Duration.zero],
  );

  test('nearby reads constellation nodes, and LOCATION_REQUIRED becomes LocationRequired', () async {
    var shared = false;
    final server = FakeServer((o) async {
      expect(o.uri.queryParameters['scope'], 'RADIUS');
      if (!shared) {
        return (
          409,
          {'code': 'LOCATION_REQUIRED', 'detail': 'Share your location first'},
        );
      }
      return (
        200,
        {
          'nodes': [
            {
              'nodeId': 'm1',
              'firstName': 'Riya',
              'activity': 'COFFEE',
              'distanceBand': '~1 km',
              'liveCapture': true,
            },
          ],
        },
      );
    });
    final data = ApiData(client(server), clock: () => now);
    await expectLater(data.nearby(), throwsA(isA<LocationRequired>()));
    shared = true;
    final list = await data.nearby();
    expect(list.single.id, 'm1');
    expect(list.single.firstName, 'Riya');
  });

  test('a signal posts the moment and the API reaction name', () async {
    final server = FakeServer((o) async => (201, {'id': 's1'}));
    await ApiData(client(server))
        .sendSignal('m1', SignalReaction.wantToKnowMore);
    final sent = server.requests.single;
    expect(sent.method, 'POST');
    expect(sent.path, '/signals');
    expect(sent.data, {'momentId': 'm1', 'reaction': 'WANT_TO_KNOW_MORE'});
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
  });

  test(
    'history is shown oldest first; EMPATHY_CHECK becomes EmpathyCheck',
    () async {
      final server = FakeServer((o) async {
        if (o.method == 'GET') {
          return (
            200,
            [
              {
                'id': '2',
                'body': 'second',
                'mine': true,
                'sentAt': '2026-10-01T11:00:00Z',
              },
              {
                'id': '1',
                'body': 'first',
                'mine': false,
                'sentAt': '2026-10-01T10:00:00Z',
              },
            ],
          );
        }
        return (
          422,
          {
            'code': 'EMPATHY_CHECK',
            'detail': 'This might land harder than you mean.',
          },
        );
      });
      final data = ApiData(client(server));
      expect((await data.history('c1')).map((m) => m.body), [
        'first',
        'second',
      ]);
      await expectLater(
        data.send('c1', 'whatever'),
        throwsA(
          isA<EmpathyCheck>().having(
            (e) => e.reflection,
            'reflection',
            contains('harder'),
          ),
        ),
      );
    },
  );

  test('phone sign-in: a new number asks for details, then the same code signs up and stores tokens', () async {
    final server = FakeServer((o) async {
      final body = o.data as Map;
      if (o.path == '/auth/otp/request') return (202, {'challengeId': 'ch1'});
      if (!body.containsKey('displayName')) {
        return (
          409,
          {'code': 'SIGNUP_DETAILS_REQUIRED', 'detail': 'New here!'},
        );
      }
      return (
        200,
        {
          'newAccount': true,
          'token': {
            'token': 'a1',
            'refreshToken': 'r1',
            'expiresInSeconds': 900,
            'verified': false,
          },
        },
      );
    });
    final auth = ApiAuthRepository(client(server));
    final challenge = await auth.requestOtp('+919876543210');
    expect(challenge, 'ch1');
    await expectLater(
      auth.verifyOtp(
        challengeId: challenge,
        phone: '+919876543210',
        code: '123456',
      ),
      throwsA(isA<SignupDetailsRequired>()),
    );
    final state = await auth.verifyOtp(
      challengeId: challenge,
      phone: '+919876543210',
      code: '123456',
      details: SignupDetails(
        displayName: ' Asha ',
        dateOfBirth: DateTime(1999, 4, 9),
      ),
    );
    expect(state.signedIn, isTrue);
    expect(state.verified, isFalse);
    expect((await store.read())!.access, 'a1');
    final last = server.requests.last.data as Map;
    expect(last['displayName'], 'Asha');
    expect(last['dateOfBirth'], '1999-04-09');
    expect(last['consentVersion'], isNotEmpty);
    // Sign-in calls never carry a bearer token.
    expect(
      server.requests.every((r) => r.headers['Authorization'] == null),
      isTrue,
    );
  });

  test(
    'sign-out clears the session even when the server is unreachable',
    () async {
      await store.write(
        Tokens(
          access: 'a',
          refresh: 'r',
          verified: true,
          expiresAt: DateTime(2030),
        ),
      );
      final auth = ApiAuthRepository(
        client(FakeServer((o) async => (0, null))),
      );
      await auth.signOut();
      expect(await store.read(), isNull);
      expect((await auth.restore()).signedIn, isFalse);
    },
  );

  test('a liveness result without a token surfaces its message', () async {
    final server = FakeServer(
      (o) async => (
        200,
        {
          'status': 'MANUAL_REVIEW',
          'message': 'A person will review this within a day.',
        },
      ),
    );
    await expectLater(
      ApiAuthRepository(client(server)).verifyLiveness('dev-pass'),
      throwsA(
        isA<ApiError>().having((e) => e.detail, 'detail', contains('review')),
      ),
    );
  });

  test(
    'a re-issued token after the face check keeps the session refresh token',
    () async {
      await store.write(
        Tokens(
          access: 'a0',
          refresh: 'r0',
          verified: false,
          expiresAt: DateTime(2030),
        ),
      );
      final server = FakeServer(
        (o) async => (
          200,
          {
            'status': 'VERIFIED',
            'message': 'You\'re verified',
            'token': {'token': 'a1', 'expiresInSeconds': 900, 'verified': true},
          },
        ),
      );
      final state = await ApiAuthRepository(client(server))
          .verifyLiveness('dev-pass');
      expect(state.verified, isTrue);
      final saved = (await store.read())!;
      expect(saved.access, 'a1');
      expect(saved.refresh, 'r0');
    },
  );

  test(
    'a photo goes to the signed URL without the bearer token, waits for READY, then is published',
    () async {
      await store.write(
        Tokens(
          access: 'a0',
          refresh: 'r0',
          verified: true,
          expiresAt: DateTime(2030),
        ),
      );
      var polls = 0;
      final server = FakeServer((o) async {
        if (o.uri.host == 'store.test') return (200, null);
        return switch (o.path) {
          '/media/uploads' => (
            201,
            {
              'mediaRef': 'incoming/u1.jpg',
              'uploadUrl': 'http://store.test/incoming/u1.jpg?sig=abc',
              'method': 'PUT',
              'headers': {'Content-Type': 'image/jpeg', 'x-od-owner': 'u1'},
            },
          ),
          '/media/uploads/complete' => (
            200,
            {'mediaRef': 'incoming/u1.jpg', 'status': 'PROCESSING'},
          ),
          '/media/uploads/status' => (
            200,
            {
              'mediaRef': 'incoming/u1.jpg',
              'status': ++polls < 2 ? 'PROCESSING' : 'READY',
            },
          ),
          '/moments' => (201, {'id': 'm9'}),
          _ => (404, null),
        };
      });
      final data = ApiData(client(server), pollEvery: Duration.zero);

      final mediaRef = await data.upload(
        Capture(bytes: Uint8List.fromList([1, 2, 3]), contentType: 'image/jpeg'),
      );
      expect(mediaRef, 'incoming/u1.jpg');
      expect(polls, 2);
      expect(server.requests.first.data, {
        'kind': 'PHOTO',
        'contentType': 'image/jpeg',
        'sizeBytes': 3,
      });
      final put = server.requests.firstWhere((r) => r.uri.host == 'store.test');
      expect(put.method, 'PUT');
      expect(put.uri.queryParameters['sig'], 'abc');
      expect(put.headers['x-od-owner'], 'u1');
      expect(put.headers['Authorization'], isNull);
      final api = server.requests.firstWhere((r) => r.path == '/media/uploads');
      expect(api.headers['Authorization'], 'Bearer a0');

      await data.publish(
        StoryDraft(
          scope: ShareScope.nearby,
          mediaRef: mediaRef,
          caption: '  Sunrise  ',
          activity: 'trek',
        ),
      );
      expect(server.requests.last.path, '/moments');
      expect(server.requests.last.data, {
        'kind': 'PHOTO',
        'shareScope': 'PUBLIC_DISCOVERY',
        'mediaRef': 'incoming/u1.jpg',
        'capturedLive': true,
        'caption': 'Sunrise',
        'activityTag': 'trek',
      });
    },
  );

  test(
    'a words-only story needs words, and a Nearby share before the area is shared asks for it',
    () async {
      final server = FakeServer(
        (o) async => (
          409,
          {'code': 'LOCATION_REQUIRED', 'detail': 'Share your location first'},
        ),
      );
      final data = ApiData(client(server));
      await expectLater(
        data.publish(const StoryDraft(scope: ShareScope.friends, caption: ' ')),
        throwsA(isA<CaptionRequired>()),
      );
      expect(server.requests, isEmpty);

      await expectLater(
        data.publish(
          const StoryDraft(scope: ShareScope.nearby, caption: 'Filter coffee'),
        ),
        throwsA(isA<LocationRequired>()),
      );
      expect(server.requests.single.data, {
        'kind': 'TEXT',
        'shareScope': 'PUBLIC_DISCOVERY',
        'caption': 'Filter coffee',
      });
    },
  );

  test('an upload the server rejects surfaces its reason', () async {
    final server = FakeServer((o) async {
      if (o.uri.host == 'store.test') return (200, null);
      return switch (o.path) {
        '/media/uploads' => (
          201,
          {'mediaRef': 'incoming/u2.mp4', 'uploadUrl': 'http://store.test/u2'},
        ),
        _ => (
          200,
          {'status': 'REJECTED', 'rejectReason': 'Videos can be up to 60 s'},
        ),
      };
    });
    await expectLater(
      ApiData(client(server)).upload(
        Capture(
          bytes: Uint8List.fromList([1]),
          contentType: 'video/mp4',
          video: true,
        ),
      ),
      throwsA(
        isA<MediaRejected>().having((e) => e.reason, 'reason', contains('60')),
      ),
    );
    expect(server.requests.first.data['kind'], 'VIDEO');
  });
}
