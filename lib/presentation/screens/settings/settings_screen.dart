import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../application/extensions/extensions_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/settings_row.dart';

/// Settings, as designed. Rows that lead nowhere yet are disabled and say
/// what they are waiting on, rather than being present and inert.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Local until there is a settings store to persist them (Phase 5).
  bool _wifiOnly = true;
  bool _deleteAfterWatching = false;
  bool _nsfw = false;

  void _pending(String what) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what arrives with the extension host.')),
  );

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
                  toggle: _nsfw,
                  onToggle: (v) => setState(() => _nsfw = v),
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
                  value: '0 B',
                  onTap: () => context.push('/downloads'),
                ),
                SettingsRow(
                  icon: Icons.wifi,
                  title: 'Only download on Wi-Fi',
                  toggle: _wifiOnly,
                  onToggle: (v) => setState(() => _wifiOnly = v),
                ),
                SettingsRow(
                  icon: Icons.auto_delete_outlined,
                  title: 'Delete after watching',
                  summary: 'Removes the file once an episode finishes',
                  toggle: _deleteAfterWatching,
                  onToggle: (v) => setState(() => _deleteAfterWatching = v),
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
                  summary: 'Needs a source that reports qualities',
                  enabled: false,
                  onTap: () => _pending('Quality selection'),
                ),
                SettingsRow(
                  icon: Icons.closed_caption_outlined,
                  title: 'Subtitle language',
                  summary: 'Needs a source that reports tracks',
                  enabled: false,
                  onTap: () => _pending('Subtitle selection'),
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
                  onTap: () => _pending('Opening links'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
