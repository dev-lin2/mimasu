import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/extensions/extensions_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/extension/extension_repo.dart';
import '../../../domain/entities/extension/extension_repo_index.dart';
import '../../widgets/kind_chip.dart';
import '../../widgets/section_head.dart';

/// The Extensions screen from `docs/design.pen`, wired to real repository data.
///
/// Installing is not implemented yet, so the Install action is inert and says
/// so — better than a button that silently does nothing.
class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    context.read<ExtensionsCubit>().addRepo(url);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ExtensionsCubit, ExtensionsState>(
      listener: (context, state) {
        if (state.status == ExtensionsStatus.ready &&
            state.error == null &&
            state.index != null) {
          _urlController.clear();
        }
      },
      builder: (context, state) {
        final cubit = context.read<ExtensionsCubit>();
        return Scaffold(
          appBar: AppBar(title: const Text('Extensions')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                8,
                AppSpace.gutter,
                32,
              ),
              children: [
                _AddRepoCard(
                  controller: _urlController,
                  busy: state.busy,
                  onSubmit: _submit,
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(
                    message: state.error!,
                    onDismiss: cubit.dismissError,
                  ),
                ],
                const SizedBox(height: 24),
                if (state.repos.isNotEmpty) ...[
                  _RepoStrip(
                    repos: state.repos,
                    selected: state.selected,
                    onSelect: cubit.select,
                    onRemove: cubit.removeRepo,
                  ),
                  const SizedBox(height: 24),
                ],
                if (state.status == ExtensionsStatus.loading || state.busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.index != null)
                  ..._catalogue(state)
                else if (state.repos.isEmpty)
                  const _NoReposYet(),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _catalogue(ExtensionsState state) {
    final repo = state.selected;
    final supported = state.supported;
    final unsupported = state.unsupported;

    return [
      if (repo != null) _RepoSummary(repo: repo),
      const SizedBox(height: 22),
      SectionHead(
        title: 'Installable',
        trailing: '${supported.length}',
      ),
      const SizedBox(height: 14),
      if (supported.isEmpty)
        const _Note(
          'Nothing in this repository can run in Mimasu. Every entry is '
          'listed below with the reason.',
        )
      else
        for (final e in supported.take(40)) _EntryRow(entry: e),
      if (unsupported.isNotEmpty) ...[
        const SizedBox(height: 26),
        SectionHead(
          title: 'Not supported',
          trailing: '${unsupported.length}',
        ),
        const SizedBox(height: 14),
        for (final e in unsupported.take(40)) _EntryRow(entry: e),
        if (unsupported.length > 40)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${unsupported.length - 40} more not shown.',
              style: AppText.meta,
            ),
          ),
      ],
    ];
  }
}

class _AddRepoCard extends StatelessWidget {
  const _AddRepoCard({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ADD A REPOSITORY', style: AppText.kicker),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !busy,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => onSubmit(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'https://…/index.pb',
                    hintStyle: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.ground,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: busy ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.ground,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Text(
            'Paste a repository URL — index.min.json or index.pb — or the '
            'folder holding one. Mimasu ships none.',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepoStrip extends StatelessWidget {
  const _RepoStrip({
    required this.repos,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
  });

  final List<ExtensionRepo> repos;
  final ExtensionRepo? selected;
  final void Function(ExtensionRepo) onSelect;
  final void Function(ExtensionRepo) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('REPOSITORIES', style: AppText.kicker),
        const SizedBox(height: 12),
        for (final repo in repos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => onSelect(repo),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: repo.id == selected?.id
                      ? AppColors.surfaceRaised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    top: const BorderSide(color: AppColors.outline),
                    right: const BorderSide(color: AppColors.outline),
                    bottom: const BorderSide(color: AppColors.outline),
                    left: BorderSide(
                      color: repo.id == selected?.id
                          ? AppColors.accent
                          : AppColors.outline,
                      width: repo.id == selected?.id ? 3 : 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            repo.displayName,
                            style: AppText.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${repo.format.name} · '
                            '${repo.supportedCount} of ${repo.extensionCount} usable',
                            style: AppText.meta,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => onRemove(repo),
                      icon: const Icon(Icons.close, size: 18),
                      color: AppColors.textTertiary,
                      tooltip: 'Remove repository',
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RepoSummary extends StatelessWidget {
  const _RepoSummary({required this.repo});
  final ExtensionRepo repo;

  @override
  Widget build(BuildContext context) {
    final key = repo.signingKeySha256;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(repo.displayName, style: AppText.sectionTitle),
          const SizedBox(height: 8),
          Text(
            '${repo.extensionCount} extensions · read as ${repo.format.name}',
            style: AppText.meta,
          ),
          if (key != null && key.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.key, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Declares key ${key.substring(0, 8)}…'
                    '${key.substring(key.length - 4)}',
                    style: AppText.meta,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'A repository vouching for its own key proves nothing. Each APK '
              'is fingerprinted before it can be trusted.',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final ExtensionEntry entry;

  @override
  Widget build(BuildContext context) {
    final reason = entry.unsupportedReason;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              entry.isSupported ? Icons.extension : Icons.block,
              size: 18,
              color: entry.isSupported
                  ? AppColors.textSecondary
                  : AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        style: AppText.body.copyWith(
                          color: entry.isSupported
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    KindChip(
                      label: 'APK',
                      tone: entry.isSupported
                          ? KindChipTone.ok
                          : KindChipTone.dim,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (entry.sources.isNotEmpty)
                      entry.sources.length == 1
                          ? entry.sources.single.lang
                          : '${entry.sources.length} sources',
                    'v${entry.versionName}',
                    if (entry.libVersion != null) 'lib ${entry.libVersion}',
                  ].join(' · '),
                  style: AppText.meta,
                ),
                if (reason != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    reason,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (entry.isSupported) ...[
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Installing arrives with the extension host.'),
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Install',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 17,
            color: AppColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(
              Icons.close,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoReposYet extends StatelessWidget {
  const _NoReposYet();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 30, 20, 28),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.folder_open,
            color: AppColors.accent,
            size: 24,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'No repositories yet',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Add one above to see the extensions it offers. Mimasu does not '
          'ship a repository, so the choice of who to trust is yours.',
          textAlign: TextAlign.center,
          style: AppText.bodySecondary,
        ),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpace.radiusCard),
    ),
    child: Text(text, style: AppText.bodySecondary),
  );
}
