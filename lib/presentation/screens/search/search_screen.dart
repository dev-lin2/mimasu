import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/empty_state.dart';

/// Search queries an installed source, so it cannot work before one is
/// running. The field is shown but disabled rather than hidden, so the screen
/// explains itself instead of looking broken.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          4,
          AppSpace.gutter,
          32,
        ),
        children: [
          const Text('Search', style: AppText.screenTitle),
          const SizedBox(height: 20),
          TextField(
            enabled: false,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.textTertiary,
              ),
              hintText: 'Install a source to search',
              hintStyle: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
              filled: true,
              fillColor: AppColors.surfaceRaised,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpace.radiusCard),
                borderSide: BorderSide.none,
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpace.radiusCard),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          EmptyState(
            icon: Icons.search_off,
            title: 'Search needs a source',
            body:
                'Results come from the sources you install, not from a '
                'catalogue Mimasu ships. There is nothing to search yet.',
            primaryLabel: 'Add a source',
            primaryIcon: Icons.add,
            onPrimary: () => context.push('/extensions'),
          ),
        ],
      ),
    ),
  );
}
