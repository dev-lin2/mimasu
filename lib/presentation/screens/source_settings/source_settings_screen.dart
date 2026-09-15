import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/source_settings/source_settings_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/source/source_setting.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/settings_row.dart';

/// Settings an extension declared for itself.
///
/// Everything here comes from the source. Mimasu neither knows nor invents
/// what these mean — the titles, options and defaults are the extension's own
/// words, which is why nothing on this screen is translated or reworded.
class SourceSettingsScreen extends StatefulWidget {
  const SourceSettingsScreen({super.key});

  @override
  State<SourceSettingsScreen> createState() => _SourceSettingsScreenState();
}

class _SourceSettingsScreenState extends State<SourceSettingsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SourceSettingsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourceSettingsCubit, SourceSettingsState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(state.source.sourceName)),
          body: switch (state.status) {
            SourceSettingsStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            SourceSettingsStatus.failure => Padding(
              padding: const EdgeInsets.all(AppSpace.gutter),
              child: EmptyState(
                icon: Icons.error_outline,
                title: 'Could not read settings',
                body: state.error ?? 'The source did not say why.',
                tone: EmptyStateTone.problem,
                primaryLabel: 'Try again',
                primaryIcon: Icons.refresh,
                onPrimary: () => context.read<SourceSettingsCubit>().load(),
              ),
            ),
            SourceSettingsStatus.ready when state.hasNone => const Padding(
              padding: EdgeInsets.all(AppSpace.gutter),
              child: EmptyState(
                icon: Icons.tune,
                title: 'Nothing to configure',
                body:
                    'This source declares no settings of its own. That is '
                    'normal — most do not.',
              ),
            ),
            SourceSettingsStatus.ready => ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                12,
                AppSpace.gutter,
                32,
              ),
              children: [
                const Text(
                  'These come from the extension itself. Mimasu passes them '
                  'through without interpreting them.',
                  style: AppText.meta,
                ),
                const SizedBox(height: 18),
                for (final setting in state.settings)
                  _SettingRow(setting: setting),
              ],
            ),
          },
        );
      },
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.setting});

  final SourceSetting setting;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SourceSettingsCubit>();

    return switch (setting.kind) {
      SourceSettingKind.toggle => SettingsRow(
        icon: Icons.tune,
        title: setting.title,
        summary: setting.summary,
        toggle: setting.isOn,
        onToggle: (v) => cubit.set(setting, v.toString()),
      ),

      SourceSettingKind.list => SettingsRow(
        icon: Icons.list,
        title: setting.title,
        summary: setting.summary,
        value: setting.displayValue,
        onTap: () => _pickOne(context, cubit),
      ),

      SourceSettingKind.multiList => SettingsRow(
        icon: Icons.checklist,
        title: setting.title,
        summary: setting.summary,
        value: '${setting.selected.length} selected',
        onTap: () => _pickMany(context, cubit),
      ),

      SourceSettingKind.text => SettingsRow(
        icon: Icons.edit_outlined,
        title: setting.title,
        summary: setting.summary,
        value: (setting.value ?? '').isEmpty ? 'Not set' : setting.value,
        onTap: () => _editText(context, cubit),
      ),

      // Shown rather than hidden: the user should know the source has a
      // setting they cannot reach from here.
      SourceSettingKind.unsupported => SettingsRow(
        icon: Icons.help_outline,
        title: setting.title,
        summary: 'This kind of setting is not supported yet',
        enabled: false,
      ),
    };
  }

  Future<void> _pickOne(
    BuildContext context,
    SourceSettingsCubit cubit,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            _SheetTitle(setting.title),
            for (var i = 0; i < setting.entryValues.length; i++)
              ListTile(
                dense: true,
                leading: Icon(
                  setting.entryValues[i] == setting.value
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: setting.entryValues[i] == setting.value
                      ? AppColors.accent
                      : AppColors.textTertiary,
                ),
                title: Text(
                  i < setting.entries.length
                      ? setting.entries[i]
                      : setting.entryValues[i],
                  style: AppText.body,
                ),
                onTap: () => Navigator.of(sheet).pop(setting.entryValues[i]),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await cubit.set(setting, picked);
  }

  Future<void> _pickMany(
    BuildContext context,
    SourceSettingsCubit cubit,
  ) async {
    final chosen = {...setting.selected};
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet2, setSheetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              _SheetTitle(setting.title),
              for (var i = 0; i < setting.entryValues.length; i++)
                CheckboxListTile(
                  dense: true,
                  value: chosen.contains(setting.entryValues[i]),
                  title: Text(
                    i < setting.entries.length
                        ? setting.entries[i]
                        : setting.entryValues[i],
                    style: AppText.body,
                  ),
                  activeColor: AppColors.accent,
                  onChanged: (on) => setSheetState(() {
                    if (on ?? false) {
                      chosen.add(setting.entryValues[i]);
                    } else {
                      chosen.remove(setting.entryValues[i]);
                    }
                  }),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  onPressed: () => Navigator.of(sheet).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.ground,
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved ?? false) {
      await cubit.set(setting, chosen.join(SourceSetting.separator));
    }
  }

  Future<void> _editText(
    BuildContext context,
    SourceSettingsCubit cubit,
  ) async {
    final controller = TextEditingController(text: setting.value ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text(setting.title, style: AppText.body),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved ?? false) await cubit.set(setting, controller.text);
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
    child: Text(
      text,
      style: AppText.body.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}
