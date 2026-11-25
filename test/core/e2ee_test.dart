import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/e2ee.dart';
import 'package:oneday_app/core/network/api_client.dart';
import 'package:oneday_app/core/network/token_store.dart';

import '../support/fake_server.dart';

/// A key directory and ciphertext relay for two people, Asha (token `a`) and Ravi (token `b`), connected by
/// `c1` with conversation `v1`. It behaves like the backend's e2ee module for what the app uses.
class _KeyServer {
  final _devices = <String, Map<int, Map<String, dynamic>>>{'a': {}, 'b': {}};
  final _inbox = <String, List<Map<String, dynamic>>>{};
  final commitments = <String, String>{};
  var _nextId = 1;

  String _user(RequestOptions o) =>
      (o.headers['Authorization'] as String).substring('Bearer '.length);

  String _other(String user) => user == 'a' ? 'b' : 'a';

  Map<String, dynamic> _bundle(int deviceId, Map<String, dynamic> d) {
    final preKeys = d['oneTimePreKeys'] as List;
    final oneTime = preKeys.isEmpty ? null : preKeys.removeAt(0);
    return {
      'deviceId': deviceId,
      'registrationId': d['registrationId'],
      'identityKey': d['identityKey'],
      'signedPreKey': d['signedPreKey'],
      'oneTimePreKey': ?oneTime,
    };
  }

  Future<(int, Object?)> handle(RequestOptions o) async {
    final user = _user(o);
    final mine = _devices[user]!;
    final path = o.path;
    if (o.method == 'GET' && path == '/e2ee/devices') {
      return (
        200,
        [
          for (final e in mine.entries)
            {
              'deviceId': e.key,
              'oneTimePreKeysLeft': (e.value['oneTimePreKeys'] as List).length,
            },
        ],
      );
    }
    if (o.method == 'POST' && path == '/e2ee/devices') {
      final body = Map<String, dynamic>.from(o.data as Map);
      body['oneTimePreKeys'] = List.of(body['oneTimePreKeys'] as List);
      final id = _nextId++;
      mine[id] = body;
      return (201, {'deviceId': id, 'oneTimePreKeysLeft': (body['oneTimePreKeys'] as List).length});
    }
    if (path == '/e2ee/connections/c1/bundles') {
      return (200, [for (final e in _devices[_other(user)]!.entries) _bundle(e.key, e.value)]);
    }
    final ownBundles = RegExp(r'^/e2ee/devices/(\d+)/bundles$').firstMatch(path);
    if (ownBundles != null) {
      final me = int.parse(ownBundles.group(1)!);
      return (
        200,
        [
          for (final e in mine.entries)
            if (e.key != me) _bundle(e.key, e.value),
        ],
      );
    }
    if (path == '/conversations/v1/encrypted') {
      final body = o.data as Map;
      final messageId = 'msg${_nextId++}';
      commitments[messageId] = body['commitment'] as String;
      for (final env in (body['envelopes'] as List).cast<Map>()) {
        final to = env['toSelf'] == true ? user : _other(user);
        _inbox.putIfAbsent('$to/${env['deviceId']}', () => []).add({
          'envelopeId': 'env${_nextId++}',
          'conversationId': 'v1',
          'messageId': messageId,
          'mine': to == user,
          'senderDevice': body['senderDevice'],
          'sentAt': '2026-11-18T10:00:00Z',
          'type': env['type'],
          'ciphertext': env['ciphertext'],
        });
      }
      return (201, {'id': messageId, 'mine': true, 'encrypted': true, 'sentAt': '2026-11-18T10:00:00Z'});
    }
    final inbox = RegExp(r'^/e2ee/devices/(\d+)/inbox$').firstMatch(path);
    if (inbox != null) {
      return (200, List.of(_inbox['$user/${inbox.group(1)}'] ?? const []));
    }
    final ack = RegExp(r'^/e2ee/devices/(\d+)/inbox/ack$').firstMatch(path);
    if (ack != null) {
      final done = ((o.data as Map)['envelopeIds'] as List).toSet();
      _inbox['$user/${ack.group(1)}']?.removeWhere((m) => done.contains(m['envelopeId']));
      return (200, <String, Object>{});
    }
    return (404, {'code': 'NOT_FOUND', 'detail': path});
  }
}

void main() {
  late _KeyServer keys;
  late FakeServer server;

  setUp(() {
    keys = _KeyServer();
    server = FakeServer(keys.handle);
  });

  Future<EncryptedChat> person(String token) async {
    final store = MemoryTokenStore();
    await store.write(Tokens(access: token, refresh: 'r', verified: true, expiresAt: DateTime(2030)));
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokens: store,
      dio: Dio()..httpClientAdapter = server,
      retryDelays: const [Duration.zero],
    );
    return EncryptedChat(api, MemoryKeyValueStore());
  }

  test('a message survives the round trip, and a reply goes back over the same sessions', () async {
    final asha = await person('a');
    final ravi = await person('b');
    await ravi.ensureDevice(); // Ravi's phone has secure chat set up

    final sent = await asha.send(conversationId: 'v1', connectionId: 'c1', body: 'Coffee at 5?');
    expect(sent.mine, isTrue);
    expect(sent.body, 'Coffee at 5?');

    expect(await ravi.receive(), {'v1'});
    final received = (await ravi.history('v1')).single;
    expect(received.body, 'Coffee at 5?');
    expect(received.mine, isFalse);

    // Franking: the commitment the server stored is HMAC(k, plaintext), with k inside the ciphertext.
    final commitment = crypto.Hmac(crypto.sha256, base64.decode(received.frankingKey))
        .convert(utf8.encode(received.body));
    expect(base64.encode(commitment.bytes), keys.commitments[received.messageId]);

    await ravi.send(conversationId: 'v1', connectionId: 'c1', body: 'Yes! Third Wave?');
    await asha.receive();
    expect([for (final m in await asha.history('v1')) m.body], ['Coffee at 5?', 'Yes! Third Wave?']);

    // Acknowledged envelopes are gone from the server.
    expect(await ravi.receive(), isEmpty);
  });

  test('the protocol state survives a restart of the app', () async {
    final kv = MemoryKeyValueStore();
    final store = MemoryTokenStore();
    await store.write(Tokens(access: 'a', refresh: 'r', verified: true, expiresAt: DateTime(2030)));
    ApiClient api() => ApiClient(
      baseUrl: 'http://api.test',
      tokens: store,
      dio: Dio()..httpClientAdapter = server,
      retryDelays: const [Duration.zero],
    );

    final first = await EncryptedChat(api(), kv).ensureDevice();
    final again = await EncryptedChat(api(), kv).ensureDevice();
    expect(again, first, reason: 'the same install keeps its device');
    expect(
      server.requests.where((r) => r.method == 'POST' && r.path == '/e2ee/devices'),
      hasLength(1),
    );
  });
}
