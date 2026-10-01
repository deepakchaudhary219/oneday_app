import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design_system/design_system.dart';
import 'features/gallery/gallery_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/signals/signals_screen.dart';

/// Deep-linkable routes (pushes and links land here). In-surface navigation (story viewer, threads) uses
/// pushed routes on top.
final appRouter = GoRouter(
  routes: [
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
  ],
);

class OneDayApp extends StatelessWidget {
  const OneDayApp({super.key, this.router});

  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'OneDay',
      debugShowCheckedModeBanner: false,
      theme: OdTheme.light(),
      darkTheme: OdTheme.dark(),
      themeMode:
          ThemeMode.dark, // dark-first: camera, stories and night use dominate
      routerConfig: router ?? appRouter,
    );
  }
}
