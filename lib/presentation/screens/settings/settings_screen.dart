import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../application/browse/browse_cubit.dart';
import '../../../application/downloads/downloads_cubit.dart';
import '../../../application/extensions/extensions_cubit.dart';
import '../../../core/di/locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/storage/app_prefs.dart';
import '../../widgets/settings_row.dart';

/// Settings, as designed. Rows that lead nowhere yet are disabled and say
/// what they are waiting on, rather than being present and inert.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppPrefs _prefs = locator<AppPrefs>();

  /// Written straight through to storage. The rebuild is only so the row
  /// redraws — the preference is already saved by the time it happens.
  Future<void> _set(Future<void> Function() write) async {
    await write();
    if (mounted) setState(() {});
  }

  /// The only way anyone gets this app is by building it, so the link to the
  /// repository is a functional part of the product rather than a credit.
  static final _repository = Uri.parse('https://github.com/dev-lin2/mimasu');

  Future<void> _openSourceCode() async {
    final opened = await launchUrl(
      _repository,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No browser to open $_repository')),
      );
    }
  }

  Future<void> _choose({
    required String title,
    required List<String> options,
    required String current,
    required Future<void> Function(String) onPick,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                title,
                style: AppText.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final option in options)
              ListTile(
                dense: true,
                leading: Icon(
                  option == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: option == current
                      ? AppColors.accent
                      : AppColors.textTertiary,
                ),
                title: Text(option, style: AppText.body),
                onTap: () => Navigator.of(sheet).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await _set(() => onPick(picked));
  }

  @override
  Widget build(BuildContext context) {
    final repoCount = context.select<ExtensionsCubit, int>(
      (c) => c.state.repos.length,
    );
    final downloadSize = context.select<DownloadsCubit, String>(
      (c) => c.state.sizeOnDiskLabel,
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
            const Text('Settings', style: AppText.screenTitle),
            const SizedBox(height: 26),

            SettingsGroup(
              label: 'Content',
              children: [
                SettingsRow(
                  icon: Icons.extension_outlined,
                  title: 'Extensions',
                  value: repoCount == 0
                      ? 'none added'
                      : '$repoCount ${repoCount == 1 ? 'repo' : 'repos'}',
                  onTap: () => context.push('/extensions'),
                ),
                SettingsRow(
                  icon: Icons.visibility_off_outlined,
                  title: 'Show NSFW sources',
                  summary: 'Hidden unless a repository marks them',
                  toggle: _prefs.showNsfwSources,
                  // Browse holds its source list in memory, so flipping this
                  // has to tell it to look again or the change appears to
                  // have been ignored until the next launch.
                  onToggle: (v) {
                    // Read the cubit before awaiting: the context must not be
                    // touched after the write completes.
                    final browse = context.read<BrowseCubit>();
                    _set(() async {
                      await _prefs.setShowNsfwSources(v);
                      await browse.refreshSources();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 26),

            SettingsGroup(
              label: 'Downloads',
              children: [
                SettingsRow(
                  icon: Icons.folder_outlined,
                  title: 'Downloads',
                  value: downloadSize,
                  onTap: () => context.push('/downloads'),
                ),
                SettingsRow(
                  icon: Icons.wifi,
                  title: 'Only download on Wi-Fi',
                  toggle: _prefs.downloadOnWifiOnly,
                  onToggle: (v) => _set(() => _prefs.setDownloadOnWifiOnly(v)),
                ),
                SettingsRow(
                  icon: Icons.auto_delete_outlined,
                  title: 'Delete after watching',
                  summary: 'Removes the file once an episode finishes',
                  toggle: _prefs.deleteAfterWatching,
                  onToggle: (v) =>
                      _set(() => _prefs.setDeleteAfterWatching(v)),
                ),
              ],
            ),
            const SizedBox(height: 26),

            SettingsGroup(
              label: 'Playback',
              children: [
                SettingsRow(
                  icon: Icons.hd_outlined,
                  title: 'Preferred quality',
                  summary: 'Falls back to the source order when unavailable',
                  value: _prefs.preferredQuality,
                  onTap: () => _choose(
                    title: 'Preferred quality',
                    options: kQualityOptions,
                    current: _prefs.preferredQuality,
                    onPick: _prefs.setPreferredQuality,
                  ),
                ),
                SettingsRow(
                  icon: Icons.closed_caption_outlined,
                  title: 'Subtitle language',
                  summary: 'Matched against whatever the source calls a track',
                  value: _prefs.subtitleLanguage,
                  onTap: () => _choose(
                    title: 'Subtitle language',
                    options: kSubtitleLanguages,
                    current: _prefs.subtitleLanguage,
                    onPick: _prefs.setSubtitleLanguage,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),

            SettingsGroup(
              label: 'Appearance',
              children: [
                SettingsRow(
                  icon: Icons.dark_mode_outlined,
                  title: 'Theme',
                  summary: 'Dark only; a light theme is not designed',
                  value: 'Dark',
                  enabled: false,
                ),
              ],
            ),
            const SizedBox(height: 26),

            SettingsGroup(
              label: 'Help',
              children: [
                SettingsRow(
                  icon: Icons.explore_outlined,
                  title: 'Help & Setup',
                  onTap: () => context.push('/help'),
                ),
                SettingsRow(
                  icon: Icons.memory,
                  title: 'Extension host probe',
                  summary: 'Diagnostic: what this device actually reports',
                  onTap: () => context.push('/host-probe'),
                ),
              ],
            ),
            const SizedBox(height: 26),

            SettingsGroup(
              label: 'About',
              children: [
                const SettingsRow(
                  icon: Icons.info_outline,
                  title: 'Version',
                  value: '0.1.0 · debug',
                  enabled: false,
                ),
                SettingsRow(
                  icon: Icons.code,
                  title: 'Source code',
                  summary: 'Fork it and build your own APK',
                  onTap: _openSourceCode,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
