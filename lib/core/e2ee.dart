import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'models.dart';
import 'network/api_client.dart';
import 'network/api_error.dart';

// End-to-end encrypted Friend Mode chat (docs/08-flutter-integration.md §8). The server is a key directory and a
// ciphertext relay: it never sees a private key or a message. This file holds the Signal protocol state for this
// install (persisted in secure storage), registers the device, encrypts once per device, and decrypts the inbox.
//
// The libsignal_protocol_dart calls follow its Signal-port API as of 0.7.x; check them against the resolved
// version when the app is first compiled.

/// A tiny string store, so the protocol state can live in secure storage on a phone and in memory in tests.
abstract interface class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

String _b64(List<int> bytes) => base64.encode(bytes);

Uint8List _unb64(String value) => base64.decode(value);

/// The Signal protocol state for this install: identity, prekeys, sessions and trusted identities, kept in
/// memory and written through to [KeyValueStore] on every change as one JSON document.
class PersistentSignalStore implements SignalProtocolStore {
  PersistentSignalStore._(this._kv, this._identity, this._registrationId);

  static const _key = 'oneday.e2ee.state';

  final KeyValueStore _kv;
  final IdentityKeyPair _identity;
  final int _registrationId;
  final _preKeys = <int, Uint8List>{};
  final _signedPreKeys = <int, Uint8List>{};
  final _sessions = <String, Uint8List>{};
  final _trusted = <String, Uint8List>{};

  /// Server-side device id once registered.
  int? deviceId;

  /// The next one-time prekey id to generate.
  int nextPreKeyId = 1;

  /// Loads the saved state, or null when this install has none yet.
  static Future<PersistentSignalStore?> load(KeyValueStore kv) async {
    final raw = await kv.read(_key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final store = PersistentSignalStore._(
        kv,
        IdentityKeyPair.fromSerialized(_unb64(j['identity'] as String)),
        j['registrationId'] as int,
      )
        ..deviceId = j['deviceId'] as int?
        ..nextPreKeyId = j['nextPreKeyId'] as int? ?? 1;
      Map<String, dynamic> map(String k) =>
          (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
      map('preKeys').forEach((k, v) => store._preKeys[int.parse(k)] = _unb64(v as String));
      map('signedPreKeys').forEach(
        (k, v) => store._signedPreKeys[int.parse(k)] = _unb64(v as String),
      );
      map('sessions').forEach((k, v) => store._sessions[k] = _unb64(v as String));
      map('trusted').forEach((k, v) => store._trusted[k] = _unb64(v as String));
      return store;
    } catch (_) {
      return null; // unreadable: this install starts over as a new device
    }
  }

  /// A brand-new identity for this install.
  static PersistentSignalStore create(KeyValueStore kv) => PersistentSignalStore._(
    kv,
    generateIdentityKeyPair(),
    generateRegistrationId(false),
  );

  Future<void> save() => _kv.write(
    _key,
    jsonEncode({
      'identity': _b64(_identity.serialize()),
      'registrationId': _registrationId,
      'deviceId': deviceId,
      'nextPreKeyId': nextPreKeyId,
      'preKeys': {for (final e in _preKeys.entries) '${e.key}': _b64(e.value)},
      'signedPreKeys': {
        for (final e in _signedPreKeys.entries) '${e.key}': _b64(e.value),
      },
      'sessions': {for (final e in _sessions.entries) e.key: _b64(e.value)},
      'trusted': {for (final e in _trusted.entries) e.key: _b64(e.value)},
    }),
  );

  /// Forgets everything (signed out: the server unlinks this device).
  Future<void> wipe() => _kv.delete(_key);

  static String _address(SignalProtocolAddress a) => '${a.getName()}#${a.getDeviceId()}';

  // ---- IdentityKeyStore

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async => _identity;

  @override
  Future<int> getLocalRegistrationId() async => _registrationId;

  /// Trust on first use: the first identity seen for an address is kept; a changed one is accepted and recorded
  /// (the other person reinstalled), as the Signal apps do by default.
  @override
  Future<bool> saveIdentity(SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;
    final key = _address(address);
    final next = identityKey.serialize();
    final previous = _trusted[key];
    _trusted[key] = next;
    await save();
    return previous != null && !_same(previous, next);
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async => true;

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final bytes = _trusted[_address(address)];
    return bytes == null ? null : IdentityKey.fromBytes(bytes, 0);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- PreKeyStore

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final bytes = _preKeys[preKeyId];
    if (bytes == null) throw InvalidKeyIdException('No prekey $preKeyId');
    return PreKeyRecord.fromBuffer(bytes);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    _preKeys[preKeyId] = record.serialize();
    await save();
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async => _preKeys.containsKey(preKeyId);

  @override
  Future<void> removePreKey(int preKeyId) async {
    _preKeys.remove(preKeyId);
    await save();
  }

  // ---- SignedPreKeyStore

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final bytes = _signedPreKeys[signedPreKeyId];
    if (bytes == null) throw InvalidKeyIdException('No signed prekey $signedPreKeyId');
    return SignedPreKeyRecord.fromSerialized(bytes);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async => [
    for (final bytes in _signedPreKeys.values) SignedPreKeyRecord.fromSerialized(bytes),
  ];

  @override
  Future<void> storeSignedPreKey(int signedPreKeyId, SignedPreKeyRecord record) async {
    _signedPreKeys[signedPreKeyId] = record.serialize();
    await save();
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      _signedPreKeys.containsKey(signedPreKeyId);

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    _signedPreKeys.remove(signedPreKeyId);
    await save();
  }

  // ---- SessionStore

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final bytes = _sessions[_address(address)];
    return bytes == null ? SessionRecord() : SessionRecord.fromSerialized(bytes);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async => [
    for (final key in _sessions.keys)
      if (key.startsWith('$name#')) int.parse(key.substring(name.length + 1)),
  ];

  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) async {
    _sessions[_address(address)] = record.serialize();
    await save();
  }

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      _sessions.containsKey(_address(address));

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    _sessions.remove(_address(address));
    await save();
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    _sessions.removeWhere((key, _) => key.startsWith('$name#'));
    await save();
  }
}

/// A message decrypted on this phone. The server keeps no plaintext, so this is the only copy.
class DecryptedMessage {
  const DecryptedMessage({
    required this.messageId,
    required this.body,
    required this.mine,
    required this.sentAt,
    required this.frankingKey,
  });

  final String messageId;
  final String body;
  final bool mine;
  final DateTime sentAt;

  /// Lets the recipient prove what was sent if they report it (message franking).
  final String frankingKey;

  Map<String, Object> toJson() => {
    'id': messageId,
    'body': body,
    'mine': mine,
    'at': sentAt.toUtc().toIso8601String(),
    'k': frankingKey,
  };

  factory DecryptedMessage.fromJson(Map<String, dynamic> j) => DecryptedMessage(
    messageId: j['id'] as String,
    body: j['body'] as String? ?? '',
    mine: j['mine'] as bool? ?? false,
    sentAt: DateTime.parse(j['at'] as String),
    frankingKey: j['k'] as String? ?? '',
  );

  ChatMessage toChat() => ChatMessage(id: messageId, mine: mine, body: body, sentAt: sentAt.toLocal());
}

/// Encrypted chat for one install: register, send, receive, report.
class EncryptedChat {
  EncryptedChat(this.api, this.kv, {Random? random}) : _random = random ?? Random.secure();

  final ApiClient api;
  final KeyValueStore kv;
  final Random _random;

  static const preKeyBatch = 100;
  static const topUpBelow = 20;
  static const keepMessages = 300;

  PersistentSignalStore? _store;

  // The other person's devices are addressed by conversation (the inbox names the conversation, not the
  // connection), and this person's other devices as self, so sending and receiving share one session each.
  static SignalProtocolAddress _theirs(String conversationId, int deviceId) =>
      SignalProtocolAddress('v:$conversationId', deviceId);

  static SignalProtocolAddress _mine(int deviceId) => SignalProtocolAddress('self', deviceId);

  Future<int>? _ensuring;
  Future<Set<String>>? _receiving;

  /// Makes sure this install is a registered device with prekeys, and returns its device id. Single flight:
  /// two registrations at once would create two devices.
  Future<int> ensureDevice() =>
      _ensuring ??= _ensureDevice().whenComplete(() => _ensuring = null);

  Future<int> _ensureDevice() async {
    var store = _store ??= await PersistentSignalStore.load(kv);
    if (store != null && store.deviceId != null) {
      final linked = await _deviceStillLinked(store.deviceId!);
      if (linked) return store.deviceId!;
      await store.wipe(); // unlinked on sign-out: become a new device
      store = null;
    }
    store = PersistentSignalStore.create(kv);
    _store = store;
    final identity = await store.getIdentityKeyPair();
    final signed = generateSignedPreKey(identity, 1);
    await store.storeSignedPreKey(signed.id, signed);
    final preKeys = await _newPreKeys(store);
    Map<String, dynamic> view;
    try {
      view = await api.post(
            '/e2ee/devices',
            body: {
              'identityKey': _b64(identity.getPublicKey().serialize()),
              'registrationId': await store.getLocalRegistrationId(),
              'signedPreKey': {
                'keyId': signed.id,
                'publicKey': _b64(signed.getKeyPair().publicKey.serialize()),
                'signature': _b64(signed.signature),
              },
              'oneTimePreKeys': preKeys,
            },
          )
          as Map<String, dynamic>;
    } on ApiError catch (e) {
      // This sign-in already registered a device whose keys this install lost: replace it.
      final existing = e.extras['deviceId'];
      if (e.code != 'DEVICE_EXISTS' || existing is! num) rethrow;
      await api.delete('/e2ee/devices/${existing.toInt()}');
      return _ensureDevice();
    }
    store.deviceId = (view['deviceId'] as num).toInt();
    await store.save();
    return store.deviceId!;
  }

  Future<bool> _deviceStillLinked(int deviceId) async {
    try {
      final devices = (await api.get('/e2ee/devices') as List).cast<Map<String, dynamic>>();
      final mine = devices.where((d) => d['deviceId'] == deviceId).firstOrNull;
      if (mine == null) return false;
      if (((mine['oneTimePreKeysLeft'] as num?) ?? 0) < topUpBelow) {
        await api.post(
          '/e2ee/devices/$deviceId/prekeys',
          body: {'oneTimePreKeys': await _newPreKeys(_store!)},
        );
      }
      return true;
    } on ApiError catch (e) {
      if (e.isNetwork) return true; // offline: keep what we have
      return false;
    }
  }

  Future<List<Map<String, Object>>> _newPreKeys(PersistentSignalStore store) async {
    final records = generatePreKeys(store.nextPreKeyId, preKeyBatch);
    store.nextPreKeyId += preKeyBatch;
    for (final r in records) {
      await store.storePreKey(r.id, r);
    }
    return [
      for (final r in records)
        {'keyId': r.id, 'publicKey': _b64(r.getKeyPair().publicKey.serialize())},
    ];
  }

  Future<void> _startSessions(
    PersistentSignalStore store,
    List<Map<String, dynamic>> bundles,
    SignalProtocolAddress Function(int deviceId) address,
  ) async {
    for (final b in bundles) {
      final deviceId = (b['deviceId'] as num).toInt();
      final at = address(deviceId);
      if (await store.containsSession(at)) continue;
      final signed = (b['signedPreKey'] as Map).cast<String, dynamic>();
      final oneTime = (b['oneTimePreKey'] as Map?)?.cast<String, dynamic>();
      final bundle = PreKeyBundle(
        (b['registrationId'] as num).toInt(),
        deviceId,
        oneTime == null ? null : (oneTime['keyId'] as num).toInt(),
        oneTime == null ? null : Curve.decodePoint(_unb64(oneTime['publicKey'] as String), 0),
        (signed['keyId'] as num).toInt(),
        Curve.decodePoint(_unb64(signed['publicKey'] as String), 0),
        _unb64(signed['signature'] as String),
        IdentityKey.fromBytes(_unb64(b['identityKey'] as String), 0),
      );
      await SessionBuilder(store, store, store, store, at).processPreKeyBundle(bundle);
    }
  }

  Future<List<Map<String, dynamic>>> _bundles(String path) async =>
      (await api.get(path) as List).cast<Map<String, dynamic>>();

  /// Sends [body] to every device of the other person and to this person's other devices.
  Future<ChatMessage> send({
    required String conversationId,
    required String connectionId,
    required String body,
  }) async {
    final deviceId = await ensureDevice();
    final store = _store!;
    final key = List<int>.generate(32, (_) => _random.nextInt(256));
    final frankingKey = _b64(key);
    final commitment = crypto.Hmac(crypto.sha256, key).convert(utf8.encode(body)).bytes;
    final payload = Uint8List.fromList(
      utf8.encode(jsonEncode({'v': 1, 'body': body, 'k': frankingKey})),
    );

    Future<Map<String, dynamic>> attempt() async {
      final theirs = await _bundles('/e2ee/connections/$connectionId/bundles');
      final mine = await _bundles('/e2ee/devices/$deviceId/bundles');
      await _startSessions(store, theirs, (d) => _theirs(conversationId, d));
      await _startSessions(store, mine, _mine);
      final envelopes = <Map<String, Object>>[];
      Future<void> encryptFor(SignalProtocolAddress at, int target, bool toSelf) async {
        final cipher = SessionCipher(store, store, store, store, at);
        final message = await cipher.encrypt(payload);
        envelopes.add({
          'deviceId': target,
          'toSelf': toSelf,
          'type': message.getType() == CiphertextMessage.prekeyType ? 'PREKEY' : 'MESSAGE',
          'ciphertext': _b64(message.serialize()),
        });
      }

      for (final b in theirs) {
        final d = (b['deviceId'] as num).toInt();
        await encryptFor(_theirs(conversationId, d), d, false);
      }
      for (final b in mine) {
        final d = (b['deviceId'] as num).toInt();
        await encryptFor(_mine(d), d, true);
      }
      return await api.post(
            '/conversations/$conversationId/encrypted',
            body: {
              'senderDevice': deviceId,
              'commitment': _b64(commitment),
              'envelopes': envelopes,
            },
          )
          as Map<String, dynamic>;
    }

    Map<String, dynamic> sent;
    try {
      sent = await attempt();
    } on ApiError catch (e) {
      if (e.code != 'DEVICE_LIST_MISMATCH') rethrow;
      // Someone added or replaced a device: forget sessions with stale ones and try once more.
      for (final stale in (e.extras['stale'] as List? ?? const [])) {
        if (stale is num) await store.deleteSession(_theirs(conversationId, stale.toInt()));
      }
      sent = await attempt();
    }
    final message = DecryptedMessage(
      messageId: sent['id'] as String,
      body: body,
      mine: true,
      sentAt: DateTime.parse(sent['sentAt'] as String),
      frankingKey: frankingKey,
    );
    await _remember(conversationId, [message]);
    return message.toChat();
  }

  /// Pulls this device's inbox, decrypts what it can, keeps it on the phone, and acknowledges it (the server
  /// then deletes the envelopes). Returns the conversations that got new messages. Single flight: decrypting
  /// the same envelope twice would break the ratchet.
  Future<Set<String>> receive() =>
      _receiving ??= _receive().whenComplete(() => _receiving = null);

  Future<Set<String>> _receive() async {
    final deviceId = await ensureDevice();
    final store = _store!;
    final items = (await api.get(
      '/e2ee/devices/$deviceId/inbox',
      query: {'limit': 100},
    ) as List).cast<Map<String, dynamic>>();
    if (items.isEmpty) return const {};
    final byConversation = <String, List<DecryptedMessage>>{};
    final done = <String>[];
    for (final item in items) {
      done.add(item['envelopeId'] as String);
      final mine = item['mine'] as bool? ?? false;
      final sender = (item['senderDevice'] as num).toInt();
      final conversationId = item['conversationId'] as String;
      final from = mine ? _mine(sender) : _theirs(conversationId, sender);
      final cipher = SessionCipher(store, store, store, store, from);
      final bytes = _unb64(item['ciphertext'] as String);
      try {
        final plain = item['type'] == 'PREKEY'
            ? await cipher.decrypt(PreKeySignalMessage(bytes))
            : await cipher.decryptFromSignal(SignalMessage.fromSerialized(bytes));
        final payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        byConversation.putIfAbsent(conversationId, () => []).add(
          DecryptedMessage(
            messageId: item['messageId'] as String,
            body: payload['body'] as String? ?? '',
            mine: mine,
            sentAt: DateTime.parse(item['sentAt'] as String),
            frankingKey: payload['k'] as String? ?? '',
          ),
        );
      } catch (_) {
        // Undecryptable (a session reset or a duplicate): acknowledged so it doesn't block the inbox.
      }
    }
    for (final e in byConversation.entries) {
      await _remember(e.key, e.value);
    }
    await api.post('/e2ee/devices/$deviceId/inbox/ack', body: {'envelopeIds': done});
    return byConversation.keys.toSet();
  }

  static String _historyKey(String conversationId) => 'oneday.e2ee.history.$conversationId';

  /// The messages this phone has decrypted for a conversation, oldest first.
  Future<List<DecryptedMessage>> history(String conversationId) async {
    final raw = await kv.read(_historyKey(conversationId));
    if (raw == null) return const [];
    try {
      return [
        for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          DecryptedMessage.fromJson(m),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _remember(String conversationId, List<DecryptedMessage> added) async {
    final known = {for (final m in await history(conversationId)) m.messageId: m};
    for (final m in added) {
      known[m.messageId] = m;
    }
    final ordered = known.values.toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final kept = ordered.length > keepMessages
        ? ordered.sublist(ordered.length - keepMessages)
        : ordered;
    await kv.write(_historyKey(conversationId), jsonEncode([for (final m in kept) m.toJson()]));
  }

  /// Reports an encrypted message by revealing it with its franking key, which proves it is what was sent.
  Future<String> report({
    required String conversationId,
    required DecryptedMessage message,
    required String category,
    String? details,
    bool alsoBlock = false,
  }) async {
    final json = await api.post(
      '/conversations/$conversationId/messages/${message.messageId}/report',
      body: {
        'plaintext': message.body,
        'frankingKey': message.frankingKey,
        'category': category,
        if ((details ?? '').trim().isNotEmpty) 'details': details!.trim(),
        if (alsoBlock) 'alsoBlock': true,
      },
    );
    return (json is Map ? json['message'] as String? : null) ?? 'Thanks. Our team will review this.';
  }

  /// Signed out: the server unlinks the device, so its keys are useless. Decrypted history stays on the phone.
  Future<void> forgetDevice() async {
    await (_store ?? await PersistentSignalStore.load(kv))?.wipe();
    _store = null;
  }
}
