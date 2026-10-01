import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/api_error.dart';
import 'package:oneday_app/core/network/token_store.dart';

import '../support/fake_server.dart';

void main() {
  late MemoryTokenStore store;

  setUp(() async {
    store = MemoryTokenStore();
    await store.write(
      Tokens(
        access: 'old',
        refresh: 'r1',
        verified: true,
        expiresAt: DateTime(2030),
      ),
    );
  });

  ApiClient client(FakeServer server) => ApiClient(
    baseUrl: 'http://api.test',
    tokens: store,
    dio: Dio()..httpClientAdapter = server,
    retryDelays: const [Duration.zero, Duration.zero],
  );

  test('concurrent 401s trigger exactly one refresh, and every request is retried with the new token', () async {
    var refreshes = 0;
    final server = FakeServer((o) async {
      if (o.path == '/auth/refresh') {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return (200, issued('new', 'r2'));
      }
      return o.headers['Authorization'] == 'Bearer new'
          ? (200, {'ok': o.path})
          : (401, {'code': 'TOKEN_EXPIRED', 'detail': 'expired'});
    });
    // The refresh call uses its own Dio, so route it through the same fake server.
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokens: store,
      dio: Dio()..httpClientAdapter = server,
      retryDelays: const [],
    );
    _routeRefreshThrough(server);
    final results = await Future.wait([
      api.get('/a'),
      api.get('/b'),
      api.get('/c'),
    ]);
    expect(results.map((r) => (r as Map)['ok']), ['/a', '/b', '/c']);
    expect(refreshes, 1);
    expect((await store.read())!.refresh, 'r2'); // the rotated token was saved
  });

  test(
    'a rejected refresh clears the session and announces sign-out',
    () async {
      final server = FakeServer(
        (o) async => o.path == '/auth/refresh'
            ? (401, {'code': 'SESSION_ENDED', 'detail': 'ended'})
            : (401, {'code': 'TOKEN_EXPIRED', 'detail': 'x'}),
      );
      _routeRefreshThrough(server);
      final api = client(server);
      final signedOut = api.signedOut.first;
      await expectLater(
        api.get('/me'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      await signedOut;
      expect(await store.read(), isNull);
    },
  );

  test(
    'a POST retried after a network failure reuses its Idempotency-Key',
    () async {
      var calls = 0;
      final server = FakeServer(
        (o) async => ++calls < 3 ? (0, null) : (201, {'id': 'm1'}),
      );
      final api = client(server);
      final result = await api.post(
        '/conversations/c/messages',
        body: {'body': 'hi'},
      );
      expect((result as Map)['id'], 'm1');
      final keys = server.requests
          .map((r) => r.headers['Idempotency-Key'])
          .toSet();
      expect(server.requests, hasLength(3));
      expect(keys, hasLength(1));
      expect(keys.single, isNotNull);
    },
  );

  test('problem details become typed errors with code, detail, request id and extras', () async {
    final server = FakeServer(
      (o) async => (
        422,
        {
          'status': 422,
          'code': 'EMPATHY_CHECK',
          'detail': 'This might sting.',
          'requestId': 'req-1',
          'tone': 'INSULT',
        },
      ),
    );
    final api = client(server);
    await expectLater(
      api.post('/conversations/c/messages', body: {'body': 'x'}),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'EMPATHY_CHECK')
            .having((e) => e.detail, 'detail', 'This might sting.')
            .having((e) => e.requestId, 'requestId', 'req-1')
            .having((e) => e.extras['tone'], 'tone', 'INSULT'),
      ),
    );
  });

  test('offline after retries surfaces a network error', () async {
    final api = client(FakeServer((o) async => (0, null)));
    await expectLater(
      api.get('/x'),
      throwsA(isA<ApiError>().having((e) => e.isNetwork, 'isNetwork', true)),
    );
  });

  test('anonymous calls never carry a token', () async {
    final server = FakeServer((o) async => (202, {'challengeId': 'c1'}));
    await client(server).post(
      '/auth/otp/request',
      body: {'phone': '+919876543210'},
      authenticated: false,
    );
    expect(
      server.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
  });
}

/// The client refreshes with a separate Dio so the refresh call never re-enters the auth interceptor. In tests,
/// point every new Dio's default adapter at the fake server.
void _routeRefreshThrough(FakeServer server) =>
    ApiClient.refreshAdapterForTests = server;
