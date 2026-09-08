import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/settings_row.dart';

/// Help & Setup hub. There is exactly one thing to connect now that accounts
/// are out of scope, so this leads with it rather than padding out a list.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help & Setup')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        8,
        AppSpace.gutter,
        32,
      ),
      children: [
        const Text(
          'Mimasu is empty until you add a source. Here is how that works.',
          style: AppText.bodySecondary,
        ),
        const SizedBox(height: 22),
        InkWell(
          onTap: () => context.push('/help/add-source'),
          borderRadius: BorderRadius.circular(AppSpace.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpace.radiusCard),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.extension_outlined,
                    color: AppColors.accent,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add a source',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Five steps, start to finish',
                        style: AppText.meta,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textTertiary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        SettingsGroup(
          label: 'Troubleshooting',
          children: [
            SettingsRow(
              icon: Icons.key_outlined,
              title: 'Allow installing extensions',
              summary: 'Required before any extension can install',
              onTap: () => context.push('/install-permission'),
            ),
            SettingsRow(
              icon: Icons.memory,
              title: 'What this device reports',
              summary: 'Feature names, metadata, signing keys',
              onTap: () => context.push('/host-probe'),
            ),
          ],
        ),
      ],
    ),
  );
}
