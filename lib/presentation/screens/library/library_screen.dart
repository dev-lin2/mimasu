import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/empty_state.dart';

/// Library is local only — no account, no sync (INSTRUCTIONS.md section 7).
/// The watch-state tabs are drawn but inert until there is something to hold.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  static const _tabs = ['Watching', 'Completed', 'Planning', 'Dropped'];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: Text('Library', style: AppText.screenTitle),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++) ...[
                  Column(
                    children: [
                      Text(
                        _tabs[i],
                        style: TextStyle(
                          color: i == 0
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          fontSize: 15,
                          fontWeight: i == 0
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: 22,
                        height: 2,
                        decoration: BoxDecoration(
                          color: i == 0 ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                  if (i != _tabs.length - 1) const SizedBox(width: 22),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: EmptyState(
              icon: Icons.bookmark_outline,
              title: 'Nothing saved yet',
              body:
                  'Series you save appear here, stored on this device only. '
                  'A source has to be installed first.',
              primaryLabel: 'Add a source',
              primaryIcon: Icons.add,
              onPrimary: () => context.push('/extensions'),
            ),
          ),
        ],
      ),
    ),
  );
}
