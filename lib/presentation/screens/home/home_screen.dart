import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../application/extensions/extensions_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/empty_state.dart';

/// Home. Browsing comes from an installed extension, so until the host can
/// load one there is nothing here but the honest reason why
/// (INSTRUCTIONS.md section 10 — empty states must say what to do next).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repoCount = context.select<ExtensionsCubit, int>(
      (c) => c.state.repos.length,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            4,
            AppSpace.gutter,
            32,
          ),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Mimasu', style: AppText.screenTitle),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Downloads',
                      onPressed: () => context.push('/downloads'),
                      icon: const Icon(
                        Icons.download_outlined,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Help & Setup',
                      onPressed: () => context.push('/help'),
                      icon: const Icon(
                        Icons.explore_outlined,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (repoCount == 0)
              EmptyState(
                icon: Icons.extension_outlined,
                title: 'Nothing to browse yet',
                body:
                    'Mimasu plays what you bring to it. Add a repository, '
                    'install a source, and its popular and latest titles '
                    'appear here.',
                primaryLabel: 'Add a source',
                primaryIcon: Icons.add,
                onPrimary: () => context.push('/extensions'),
                secondaryLabel: 'How sources work',
                onSecondary: () => context.push('/help/add-source'),
              )
            else
              EmptyState(
                icon: Icons.hourglass_empty,
                title: 'No source installed yet',
                body:
                    'You have added a repository, but nothing from it is '
                    'installed and running. Browsing needs a working source.',
                primaryLabel: 'Open Extensions',
                primaryIcon: Icons.extension_outlined,
                onPrimary: () => context.push('/extensions'),
              ),
            const SizedBox(height: 18),
            const _Roadmap(),
          ],
        ),
      ),
    );
  }
}

/// Deliberately visible rather than hidden: the app is mid-build, and a screen
/// that silently shows nothing reads as broken. Delete once Phase 2 lands.
class _Roadmap extends StatelessWidget {
  const _Roadmap();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('BUILD STATUS', style: AppText.kicker),
        const SizedBox(height: 10),
        for (final (done, label) in const [
          (true, 'Repository indexes — both formats, parsed and tested'),
          (true, 'Extension discovery, signature verification'),
          (false, 'extensions-lib shim — required before anything loads'),
          (false, 'Browse, episodes, playback, downloads'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 14,
                  color: done ? AppColors.ok : AppColors.textTertiary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: done
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
