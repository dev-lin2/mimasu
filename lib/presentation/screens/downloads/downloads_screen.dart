import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../application/downloads/downloads_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/downloads/download_record.dart';
import '../../../domain/entities/source/anime.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_head.dart';

/// Episodes saved to this device (INSTRUCTIONS.md §9).
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DownloadsCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DownloadsCubit, DownloadsState>(
      listenWhen: (a, b) => b.notice != null && a.notice != b.notice,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(state.notice!),
              behavior: SnackBarBehavior.floating,
            ),
          );
        context.read<DownloadsCubit>().dismissNotice();
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Downloads')),
          body: state.isEmpty
              ? const _Empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    8,
                    AppSpace.gutter,
                    32,
                  ),
                  children: [
                    if (state.active.isNotEmpty) ...[
                      const SectionHead(title: 'In progress'),
                      const SizedBox(height: 12),
                      for (final item in state.active)
                        _Row(item: item, key: ValueKey(item.record.id)),
                      const SizedBox(height: 22),
                    ],
                    if (state.finished.isNotEmpty) ...[
                      SectionHead(
                        title: 'On this device',
                        trailing: '${state.finished.length}',
                      ),
                      const SizedBox(height: 12),
                      for (final item in state.finished)
                        _Row(item: item, key: ValueKey(item.record.id)),
                      const SizedBox(height: 22),
                    ],
                    if (state.problems.isNotEmpty) ...[
                      const SectionHead(title: 'Did not finish'),
                      const SizedBox(height: 12),
                      for (final item in state.problems)
                        _Row(item: item, key: ValueKey(item.record.id)),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpace.gutter),
    child: EmptyState(
      icon: Icons.download_outlined,
      title: 'No downloads',
      body:
          'Episodes you save appear here and play without a connection. '
          'Use the download button next to an episode.',
      primaryLabel: 'Browse',
      primaryIcon: Icons.explore_outlined,
      onPrimary: () => context.go('/home'),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.item, super.key});

  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DownloadsCubit>();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpace.radiusCard),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(item: item),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.record.anime.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.record.episodeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta,
                      ),
                      const SizedBox(height: 4),
                      _Status(item: item),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Action(item: item, cubit: cubit),
              ],
            ),
            if (item.isActive) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  // Null while the total is unknown, which shows movement
                  // instead of a bar stuck at nothing.
                  value: item.fraction,
                  minHeight: 3,
                  backgroundColor: AppColors.surfaceRaised,
                  valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final url = item.record.anime.thumbnailUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 42,
        height: 60,
        child: url == null
            ? Container(color: AppColors.surfaceRaised)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(color: AppColors.surfaceRaised),
              ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final (text, colour) = switch (item.state) {
      DownloadProgressState.queued => ('Waiting', AppColors.textTertiary),
      DownloadProgressState.running => (
        item.sizeLabel.isEmpty ? 'Starting' : item.sizeLabel,
        AppColors.textSecondary,
      ),
      DownloadProgressState.completed => (
        item.sizeLabel.isEmpty ? 'Saved' : 'Saved  ·  ${item.sizeLabel}',
        AppColors.textSecondary,
      ),
      DownloadProgressState.cancelled => ('Cancelled', AppColors.textTertiary),
      DownloadProgressState.failed => (
        item.error ?? 'Failed',
        AppColors.accent,
      ),
    };

    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppText.meta.copyWith(color: colour),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.item, required this.cubit});

  final DownloadItem item;
  final DownloadsCubit cubit;

  @override
  Widget build(BuildContext context) {
    if (item.isActive) {
      return IconButton(
        tooltip: 'Cancel',
        icon: const Icon(Icons.close, size: 19, color: AppColors.textTertiary),
        onPressed: () => cubit.cancel(item.record.id),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.isFinished)
          IconButton(
            tooltip: 'Play',
            icon: const Icon(
              Icons.play_circle,
              size: 22,
              color: AppColors.accent,
            ),
            onPressed: () => context.push(
              '/player',
              extra: (item.record.anime, _episode(item.record)),
            ),
          ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(
            Icons.delete_outline,
            size: 19,
            color: AppColors.textTertiary,
          ),
          onPressed: () => cubit.remove(item.record.id),
        ),
      ],
    );
  }

  /// The player takes an [Episode]; only the url and name are needed to find
  /// the local file and label the screen.
  static Episode _episode(DownloadRecord record) => Episode(
    url: record.episodeUrl,
    name: record.episodeName,
    number: record.episodeNumber,
  );
}
