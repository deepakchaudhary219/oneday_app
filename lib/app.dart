import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'core/auth/auth_repository.dart';
import 'core/providers.dart';
import 'design_system/design_system.dart';
import 'features/auth/about_you_screen.dart';
import 'features/auth/email_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/auth/phone_screen.dart';
import 'features/auth/verify_screen.dart';
import 'features/auth/welcome_screen.dart';
import 'features/amas/amas_screen.dart';
import 'features/calls/call_screen.dart';
import 'features/capsules/capsules_screen.dart';
import 'features/dates/dates_screen.dart';
import 'features/figures/figures_screen.dart';
import 'features/gallery/gallery_screen.dart';
import 'features/live/live_screen.dart';
import 'features/plans/plans_screen.dart';
import 'features/plus/plus_screen.dart';
import 'features/relays/relay_screen.dart';
import 'features/right_now/right_now_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/signals/signals_screen.dart';
import 'features/threads/threads_screen.dart';
import 'features/together/together_screen.dart';

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
      GoRoute(
        path: '/',
        builder: (_, _) => const RealtimeRefresher(child: HomeShell()),
      ),
      GoRoute(
        path: '/chats',
        builder: (_, _) => const RealtimeRefresher(
          child: HomeShell(initialTab: HomeTab.chats),
        ),
      ),
      GoRoute(
        path: '/nearby',
        builder: (_, _) => const RealtimeRefresher(
          child: HomeShell(initialTab: HomeTab.nearby),
        ),
      ),
      GoRoute(path: '/signals', builder: (_, _) => const SignalsScreen()),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),
      GoRoute(path: '/verify', builder: (_, _) => const VerifyScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/together', builder: (_, _) => const TogetherScreen()),
      GoRoute(path: '/plans', builder: (_, _) => const PlansScreen()),
      GoRoute(path: '/dates', builder: (_, _) => const DatesScreen()),
      GoRoute(path: '/right-now', builder: (_, _) => const RightNowScreen()),
      GoRoute(path: '/threads', builder: (_, _) => const ThreadsScreen()),
      GoRoute(path: '/capsules', builder: (_, _) => const CapsulesScreen()),
      GoRoute(path: '/plus', builder: (_, _) => const PlusScreen()),
      GoRoute(path: '/ledger', builder: (_, _) => const LedgerScreen()),
      GoRoute(path: '/figures', builder: (_, _) => const FiguresScreen()),
      GoRoute(path: '/amas', builder: (_, _) => const AmasScreen()),
      GoRoute(path: '/live', builder: (_, _) => const LivesScreen()),
      GoRoute(
        path: '/relay/:momentId',
        builder: (_, state) =>
            RelayScreen(momentId: state.pathParameters['momentId']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Keeps the home surfaces current from the socket: a pushed message refreshes the chat list, a notice
/// refreshes the lists a notice can be about. Events are hints; the lists re-fetch over HTTP.
class RealtimeRefresher extends ConsumerWidget {
  const RealtimeRefresher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pushRegistrationProvider);
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      switch (event?.type) {
        case 'call':
          showIncomingCall(context, event!);
        case 'e2ee':
          // Pull and decrypt this device's inbox; the open chat re-reads what was stored.
          ref
              .read(encryptedChatProvider)
              ?.receive()
              .then((_) => ref.invalidate(conversationsProvider), onError: (Object _) {});
        case 'message':
          ref.invalidate(conversationsProvider);
        case 'notice':
          ref.invalidate(conversationsProvider);
          ref.invalidate(pendingSignalsProvider);
      }
    });
    return child;
  }
}

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
