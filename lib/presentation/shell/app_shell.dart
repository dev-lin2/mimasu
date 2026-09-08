import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// The bottom-nav shell of `docs/design.pen`: a flush Material 3
/// `NavigationBar` with a pill indicator, not the floating capsule bar the
/// pen.dev mobile guide suggests (INSTRUCTIONS.md section 10).
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.video_library_outlined, Icons.video_library, 'Library'),
    (Icons.search, Icons.search, 'Search'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        // Hairline top border; separation comes from surface steps plus
        // outlines, never shadow.
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline)),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            // Tapping the current tab returns it to its root, which is what
            // people expect from a bottom bar.
            initialLocation: index == navigationShell.currentIndex,
          ),
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final (icon, selectedIcon, label) in _destinations)
              NavigationDestination(
                icon: Icon(icon, color: AppColors.textSecondary, size: 23),
                selectedIcon: Icon(
                  selectedIcon,
                  color: AppColors.accent,
                  size: 23,
                ),
                label: label,
              ),
          ],
        ),
      ),
    );
  }
}
