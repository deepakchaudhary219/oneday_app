import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The session's tokens. The refresh token rotates on every use, so the newest one must always be saved before
/// it's needed again.
class Tokens {
  const Tokens({
    required this.access,
    required this.refresh,
    required this.verified,
    required this.expiresAt,
  });

  final String access;
  final String refresh;
  final bool verified;
  final DateTime expiresAt;

  /// From the backend's IssuedToken. Re-issued tokens (after a face check) carry no refresh token: the
  /// session's current one stays valid, so pass it as [keepRefresh].
  factory Tokens.fromIssued(
    Map<String, dynamic> json,
    DateTime now, {
    String? keepRefresh,
  }) => Tokens(
    access: json['token'] as String,
    refresh: (json['refreshToken'] as String?) ?? keepRefresh!,
    verified: json['verified'] as bool? ?? false,
    expiresAt: now.add(
      Duration(seconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 900),
    ),
  );

  Map<String, Object> toJson() => {
    'access': access,
    'refresh': refresh,
    'verified': verified,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory Tokens.fromJson(Map<String, dynamic> json) => Tokens(
    access: json['access'] as String,
    refresh: json['refresh'] as String,
    verified: json['verified'] as bool,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

abstract interface class TokenStore {
  Future<Tokens?> read();

  Future<void> write(Tokens tokens);

  Future<void> clear();
}

/// Keychain (iOS) / Keystore-backed EncryptedSharedPreferences (Android).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'oneday.session';

  final FlutterSecureStorage _storage;

  @override
  Future<Tokens?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return Tokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear(); // unreadable: start clean rather than crash on launch
      return null;
    }
  }

  @override
  Future<void> write(Tokens tokens) =>
      _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  Tokens? _tokens;

  @override
  Future<Tokens?> read() async => _tokens;

  @override
  Future<void> write(Tokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
