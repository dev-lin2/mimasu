import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/empty_state.dart';

/// Downloads. The queue is owned by a Kotlin foreground service
/// (INSTRUCTIONS.md section 9) which is not built yet, so this shows the
/// storage summary and an honestly empty queue rather than a fake one.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Downloads')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        8,
        AppSpace.gutter,
        32,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpace.radiusCard),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nothing downloaded',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text('0 B', style: AppText.meta),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Downloads are written to app-specific storage and played '
                'from disk when a local copy exists.',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const EmptyState(
          icon: Icons.download_outlined,
          title: 'No downloads',
          body:
              'Episodes you download appear here and play without a '
              'connection. Downloading arrives with the extension host.',
        ),
      ],
    ),
  );
}
