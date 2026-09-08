import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// The add-a-source guide from `docs/design.pen`. The steps describe the real
/// mechanics — index formats, the OS installer, signing keys — so the guide
/// cannot drift from what the app actually does.
class AddSourceGuideScreen extends StatelessWidget {
  const AddSourceGuideScreen({super.key});

  static const _steps = [
    (
      'Find a repository URL',
      'Repositories are hosted as index.min.json or the newer index.pb. '
          'Mimasu does not provide or recommend one — you decide who to trust.',
    ),
    (
      'Paste it into Extensions',
      'Paste the index URL, or the folder holding it. Mimasu reads the index '
          'and lists what it offers, marking anything it cannot run.',
    ),
    (
      'Allow installing extensions',
      'Extensions are Android apps, so Android has to let Mimasu install '
          'them. This is a one-time switch in system settings.',
    ),
    (
      'Install and check the key',
      "Mimasu fingerprints the APK's signing certificate. If it does not "
          'recognise the signer it asks first — an unknown key is not proof '
          'of anything bad, but it is worth a look.',
    ),
    (
      'Choose it on any title',
      'Open a title, tap Source, and pick what you installed. Episodes and '
          'download options appear underneath.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add a source')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        8,
        AppSpace.gutter,
        32,
      ),
      children: [
        const Text(
          'A source is an extension that knows how to read one site. You '
          'install it once, and it powers browsing, episode lists, playback '
          'and downloads.',
          style: AppText.bodySecondary,
        ),
        const SizedBox(height: 24),
        const Text('FIVE STEPS', style: AppText.kicker),
        const SizedBox(height: 16),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _steps[i].$1,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_steps[i].$2, style: AppText.bodySecondary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpace.radiusCard),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.public, size: 16, color: AppColors.ok),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Requests that go through Mimasu are logged per extension. '
                  'Extensions can also open their own connections, so treat '
                  'the log as useful rather than complete.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: () => context.push('/extensions'),
            icon: const Icon(Icons.extension_outlined, size: 17),
            label: const Text(
              'Open Extensions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.ground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpace.radiusCard),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
