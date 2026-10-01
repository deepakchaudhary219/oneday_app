import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'core/auth/auth_repository.dart';
import 'design_system/design_system.dart';
import 'features/auth/about_you_screen.dart';
import 'features/auth/email_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/auth/phone_screen.dart';
import 'features/auth/verify_screen.dart';
import 'features/auth/welcome_screen.dart';
import 'features/gallery/gallery_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/signals/signals_screen.dart';

/// Pure routing decision, kept separate so it can be unit-tested: where should [location] go for [auth]?
String? authRedirect(AuthState auth, String location) {
  final inAuth = location == '/welcome' || location.startsWith('/auth');
  return switch (auth.stage) {
    AuthStage.unknown => location == '/splash' ? null : '/splash',
    AuthStage.signedOut => inAuth ? null : '/welcome',
    AuthStage.signedIn => inAuth || location == '/splash' ? '/' : null,
  };
}

/// Deep-linkable routes (pushes and links land here). In-surface navigation (story viewer, threads) uses pushed
/// routes on top. The redirect follows the session, so signing in or out anywhere lands on the right screen.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = AuthRefresh(ref);
  ref.onDispose(refresh.dispose);
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (_, state) =>
        authRedirect(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/auth/phone', builder: (_, _) => const PhoneScreen()),
      GoRoute(
        path: '/auth/otp',
        redirect: (_, state) => state.extra is OtpArgs ? null : '/auth/phone',
        builder: (_, state) => OtpScreen(args: state.extra! as OtpArgs),
      ),
      GoRoute(
        path: '/auth/about',
        redirect: (_, state) => state.extra is AboutYouArgs ? null : '/welcome',
        builder: (_, state) =>
            AboutYouScreen(args: state.extra! as AboutYouArgs),
      ),
      GoRoute(path: '/auth/email', builder: (_, _) => const EmailScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeShell()),
      GoRoute(
        path: '/chats',
        builder: (_, _) => const HomeShell(initialTab: HomeTab.chats),
      ),
      GoRoute(
        path: '/nearby',
        builder: (_, _) => const HomeShell(initialTab: HomeTab.nearby),
      ),
      GoRoute(path: '/signals', builder: (_, _) => const SignalsScreen()),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),
      GoRoute(path: '/verify', builder: (_, _) => const VerifyScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class OneDayApp extends ConsumerWidget {
  const OneDayApp({super.key, this.router});

  final GoRouter? router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'OneDay',
      debugShowCheckedModeBanner: false,
      theme: OdTheme.light(),
      darkTheme: OdTheme.dark(),
      themeMode:
          ThemeMode.dark, // dark-first: camera, stories and night use dominate
      routerConfig: router ?? ref.watch(routerProvider),
    );
  }
}
