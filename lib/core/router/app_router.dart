import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/storage/app_prefs.dart';
import '../../presentation/screens/downloads/downloads_screen.dart';
import '../../presentation/screens/extensions/extensions_screen.dart';
import '../../presentation/screens/help/add_source_guide_screen.dart';
import '../../presentation/screens/help/help_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/host_probe/host_probe_screen.dart';
import '../../presentation/screens/library/library_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/permission/install_permission_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/shell/app_shell.dart';

/// The nav graph. Four tabs keep their own navigation stacks; everything
/// reached from them is pushed over the shell so the bar stays put.
GoRouter buildRouter(AppPrefs prefs) {
  final shellKey = GlobalKey<NavigatorState>();

  return GoRouter(
    initialLocation: prefs.onboardingSeen ? '/home' : '/onboarding',
    navigatorKey: shellKey,
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => OnboardingScreen(prefs: prefs),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // Pushed over the shell.
      GoRoute(
        path: '/extensions',
        builder: (context, state) => const ExtensionsScreen(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => const DownloadsScreen(),
      ),
      GoRoute(
        path: '/help',
        builder: (context, state) => const HelpScreen(),
        routes: [
          GoRoute(
            path: 'add-source',
            builder: (context, state) => const AddSourceGuideScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/install-permission',
        builder: (context, state) => const InstallPermissionScreen(),
      ),
      GoRoute(
        path: '/host-probe',
        builder: (context, state) => const HostProbeScreen(),
      ),
    ],
  );
}
