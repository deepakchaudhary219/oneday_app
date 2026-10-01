import 'dart:async';

import '../network/api_client.dart';
import '../network/api_config.dart';
import '../network/api_error.dart';

/// Where the person is in the session lifecycle. Verification is progressive (backend blueprint): you're in the
/// app as soon as you're signed in, and liveness is asked for at the first contact action, not at the door.
enum AuthStage { unknown, signedOut, signedIn }

class AuthState {
  const AuthState(this.stage, {this.verified = false});

  static const unknown = AuthState(AuthStage.unknown);
  static const signedOut = AuthState(AuthStage.signedOut);

  final AuthStage stage;
  final bool verified;

  bool get signedIn => stage == AuthStage.signedIn;
}

/// Phone sign-in found no account: ask for name, date of birth and consent, then verify the same code again.
class SignupDetailsRequired implements Exception {
  const SignupDetailsRequired();
}

class SignupDetails {
  const SignupDetails({required this.displayName, required this.dateOfBirth});

  final String displayName;
  final DateTime dateOfBirth;

  Map<String, Object> toJson() => {
    'displayName': displayName.trim(),
    'dateOfBirth': _date(dateOfBirth),
    'consentVersion': ApiConfig.consentVersion,
  };
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

abstract interface class AuthRepository {
  Future<AuthState> restore();

  /// Returns the challenge id to verify against.
  Future<String> requestOtp(String phone);

  /// Throws [SignupDetailsRequired] for a new number without [details]; the same challenge and code stay valid.
  Future<AuthState> verifyOtp({
    required String challengeId,
    required String phone,
    required String code,
    SignupDetails? details,
  });

  Future<AuthState> signInWithEmail(String email, String password);

  Future<AuthState> registerWithEmail({
    required String email,
    required String password,
    required SignupDetails details,
  });

  /// Liveness: the vendor SDK yields a session token; the dev backend accepts `dev-pass`.
  Future<AuthState> verifyLiveness(String sessionToken);

  Future<void> signOut();

  /// The session ended elsewhere (refresh rejected, signed out remotely).
  Stream<void> get sessionEnded;
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this.api);

  final ApiClient api;

  @override
  Future<AuthState> restore() async {
    final tokens = await api.tokens.read();
    return tokens == null
        ? AuthState.signedOut
        : AuthState(AuthStage.signedIn, verified: tokens.verified);
  }

  @override
  Future<String> requestOtp(String phone) async {
    final json = await api.post(
      '/auth/otp/request',
      body: {'phone': phone},
      authenticated: false,
    ) as Map<String, dynamic>;
    return json['challengeId'] as String;
  }

  @override
  Future<AuthState> verifyOtp({
    required String challengeId,
    required String phone,
    required String code,
    SignupDetails? details,
  }) async {
    try {
      final json = await api.post(
        '/auth/otp/verify',
        body: {
          'challengeId': challengeId,
          'phone': phone,
          'code': code,
          ...?details?.toJson(),
        },
        authenticated: false,
      ) as Map<String, dynamic>;
      return await _adopt(json['token'] as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.code == 'SIGNUP_DETAILS_REQUIRED') {
        throw const SignupDetailsRequired();
      }
      rethrow;
    }
  }

  @override
  Future<AuthState> signInWithEmail(String email, String password) async =>
      _adopt(
        await api.post(
          '/auth/login',
          body: {'email': email.trim(), 'password': password},
          authenticated: false,
        ) as Map<String, dynamic>,
      );

  @override
  Future<AuthState> registerWithEmail({
    required String email,
    required String password,
    required SignupDetails details,
  }) async {
    final body = {
      'email': email.trim(),
      'password': password,
      ...details.toJson(),
    };
    return _adopt(
      await api.post('/auth/register', body: body, authenticated: false)
          as Map<String, dynamic>,
    );
  }

  @override
  Future<AuthState> verifyLiveness(String sessionToken) async {
    final json = await api.post(
      '/verification/liveness',
      body: {'sessionToken': sessionToken},
    ) as Map<String, dynamic>;
    final token = json['token'] as Map<String, dynamic>?;
    if (token == null) {
      // MANUAL_REVIEW / REJECTED: still signed in, not yet verified; the message says what happens next.
      throw ApiError(
        status: 200,
        code: json['status'] as String? ?? 'NOT_VERIFIED',
        detail: json['message'] as String? ?? '',
      );
    }
    return _adopt(token);
  }

  @override
  Future<void> signOut() async {
    try {
      await api.post('/auth/logout');
    } on ApiError {
      // Signing out locally must always work, even offline.
    }
    await api.tokens.clear();
  }

  @override
  Stream<void> get sessionEnded => api.signedOut;

  Future<AuthState> _adopt(Map<String, dynamic> issued) async {
    final tokens = await api.adopt(issued);
    return AuthState(AuthStage.signedIn, verified: tokens.verified);
  }
}

/// Design/demo mode: code `123456`, liveness `dev-pass`, any email/password ≥ 12 characters.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    AuthState initial = AuthState.signedOut,
    this.latency = const Duration(milliseconds: 350),
  }) : _state = initial;

  final Duration latency;
  AuthState _state;
  final _knownPhones = <String>{};
  final _ended = StreamController<void>.broadcast();

  @override
  Future<AuthState> restore() async => _state;

  @override
  Future<String> requestOtp(String phone) async {
    await Future<void>.delayed(latency);
    return 'challenge-$phone';
  }

  @override
  Future<AuthState> verifyOtp({
    required String challengeId,
    required String phone,
    required String code,
    SignupDetails? details,
  }) async {
    await Future<void>.delayed(latency);
    if (code != '123456') {
      throw const ApiError(
        status: 401,
        code: 'OTP_INVALID',
        detail: 'That code isn\'t right',
      );
    }
    if (!_knownPhones.contains(phone)) {
      if (details == null) throw const SignupDetailsRequired();
      _knownPhones.add(phone);
    }
    return _state = const AuthState(AuthStage.signedIn);
  }

  @override
  Future<AuthState> signInWithEmail(String email, String password) async {
    await Future<void>.delayed(latency);
    if (password.length < 12) {
      throw const ApiError(
        status: 401,
        code: 'INVALID_CREDENTIALS',
        detail: 'That email and password don\'t match',
      );
    }
    return _state = const AuthState(AuthStage.signedIn);
  }

  @override
  Future<AuthState> registerWithEmail({
    required String email,
    required String password,
    required SignupDetails details,
  }) async {
    await Future<void>.delayed(latency);
    return _state = const AuthState(AuthStage.signedIn);
  }

  @override
  Future<AuthState> verifyLiveness(String sessionToken) async {
    await Future<void>.delayed(latency);
    return _state = const AuthState(AuthStage.signedIn, verified: true);
  }

  @override
  Future<void> signOut() async => _state = AuthState.signedOut;

  @override
  Stream<void> get sessionEnded => _ended.stream;

  /// Tests: simulate the server ending the session.
  void endSession() {
    _state = AuthState.signedOut;
    _ended.add(null);
  }
}
