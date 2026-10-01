@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/api_repositories.dart';
import 'package:oneday_app/core/auth/auth_repository.dart';
import 'package:oneday_app/core/location.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/token_store.dart';

/// End to end against a running backend (dev profile), using the app's real client and repositories:
///
///     ONEDAY_LIVE_API=http://localhost:8080 ONEDAY_LIVE_LOG=/path/to/backend.log flutter test test/live
///
/// ONEDAY_LIVE_LOG lets the phone test read the code the dev SMS sender logs. Skipped when unset.
void main() {
  final base = Platform.environment['ONEDAY_LIVE_API'];
  final log = Platform.environment['ONEDAY_LIVE_LOG'];
  final skip = base == null
      ? 'set ONEDAY_LIVE_API to run against a backend'
      : null;
  final run = Random().nextInt(1 << 30);

  ApiClient client(TokenStore store) =>
      ApiClient(baseUrl: base!, tokens: store);

  test('email sign-up, face check, location, nearby, budget, profile, chats, stories, sign-out', () async {
    final store = MemoryTokenStore();
    final api = client(store);
    final auth = ApiAuthRepository(api);
    final data = ApiData(api);

    var state = await auth.registerWithEmail(
      email: 'smoke$run@example.com',
      password: 'a long smoke-test passphrase',
      details: SignupDetails(
        displayName: 'Smoke',
        dateOfBirth: DateTime(1998, 5, 17),
      ),
    );
    expect(state.signedIn, isTrue);

    state = await auth.verifyLiveness('dev-pass');
    expect(state.verified, isTrue);

    // Nearby before sharing a location is a typed, recoverable state.
    await expectLater(data.nearby(), throwsA(anything));
    final shared = await ApiLocationShare(
      api,
      _Fixed(12.9716, 77.5946),
    ).share();
    expect(shared, isTrue);
    expect(await data.nearby(), isA<List<Object>>());

    final budget = await data.budget();
    expect(budget.remaining, budget.daily);
    expect((await data.me()).displayName, 'Smoke');
    expect(await data.conversations(), isEmpty);
    expect(await data.friendsStories(), isA<List<Object>>());
    expect(await data.pending(), isEmpty);

    // An access token the server rejects is refreshed transparently with the stored refresh token.
    final t = (await store.read())!;
    await store.write(
      Tokens(
        access: 'not-a-token',
        refresh: t.refresh,
        verified: t.verified,
        expiresAt: t.expiresAt,
      ),
    );
    expect((await data.me()).displayName, 'Smoke');
    expect((await store.read())!.access, isNot('not-a-token'));

    await auth.signOut();
    expect(await store.read(), isNull);
  }, skip: skip);

  test('phone: new number → details required → same code signs up → signing in again skips details', () async {
    if (log == null) {
      return markTestSkipped('set ONEDAY_LIVE_LOG to read dev SMS codes');
    }
    final phone = '+9198${(run % 100000000).toString().padLeft(8, '0')}';

    Future<String> codeFor(String challenge) async {
      for (var i = 0; i < 20; i++) {
        final m = RegExp(
          r'\[dev sms\] to \+?' + phone.substring(1) + r'.*?code is (\d{6})',
        ).allMatches(await File(log).readAsString());
        if (m.isNotEmpty) return m.last.group(1)!;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      fail('no code logged for $phone');
    }

    final store = MemoryTokenStore();
    final auth = ApiAuthRepository(client(store));
    var challenge = await auth.requestOtp(phone);
    var code = await codeFor(challenge);
    await expectLater(
      auth.verifyOtp(challengeId: challenge, phone: phone, code: code),
      throwsA(isA<SignupDetailsRequired>()),
    );
    final state = await auth.verifyOtp(
      challengeId: challenge,
      phone: phone,
      code: code,
      details: SignupDetails(
        displayName: 'Phone',
        dateOfBirth: DateTime(1995, 1, 2),
      ),
    );
    expect(state.signedIn, isTrue);
    await auth.signOut();

    challenge = await auth.requestOtp(phone);
    code = await codeFor(challenge);
    expect(
      (await auth.verifyOtp(
        challengeId: challenge,
        phone: phone,
        code: code,
      )).signedIn,
      isTrue,
    );
  }, skip: skip);
}

class _Fixed implements LocationSource {
  const _Fixed(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  Future<({double lat, double lon})?> current() async => (lat: lat, lon: lon);
}
