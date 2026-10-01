import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'auth_repository.dart';

/// The session as the UI sees it. Screens call these methods; the router follows [state].
class AuthController extends Notifier<AuthState> {
  StreamSubscription<void>? _ended;

  @override
  AuthState build() {
    final repo = ref.watch(authRepositoryProvider);
    _ended?.cancel();
    _ended = repo.sessionEnded.listen((_) => state = AuthState.signedOut);
    ref.onDispose(() => _ended?.cancel());
    Future.microtask(() async => state = await repo.restore());
    return AuthState.unknown;
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<String> requestOtp(String phone) => _repo.requestOtp(phone);

  Future<void> verifyOtp({
    required String challengeId,
    required String phone,
    required String code,
    SignupDetails? details,
  }) async => state = await _repo.verifyOtp(
    challengeId: challengeId,
    phone: phone,
    code: code,
    details: details,
  );

  Future<void> signInWithEmail(String email, String password) async =>
      state = await _repo.signInWithEmail(email, password);

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required SignupDetails details,
  }) async => state = await _repo.registerWithEmail(
    email: email,
    password: password,
    details: details,
  );

  Future<void> verifyLiveness(String sessionToken) async =>
      state = await _repo.verifyLiveness(sessionToken);

  Future<void> signOut() async {
    await _repo.signOut();
    state = AuthState.signedOut;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Bridges the auth state into a [Listenable] for go_router's `refreshListenable`.
class AuthRefresh extends ChangeNotifier {
  AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}
