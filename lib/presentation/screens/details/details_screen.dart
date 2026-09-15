import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../application/details/details_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/source/anime.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_head.dart';

/// Anime details and episode list, from `docs/design.pen`.
///
/// Everything shown comes from the source: there is no metadata service to
/// fill gaps, so absent fields are simply absent rather than invented.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DetailsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetailsCubit, DetailsState>(
      builder: (context, state) {
        final anime = state.anime;
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              _Banner(anime: anime),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    18,
                    AppSpace.gutter,
                    32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SourceRow(source: anime.source),
                      if (state.error != null) ...[
                        const SizedBox(height: 16),
                        _Problem(message: state.error!),
                      ],
                      if (anime.genres.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final g in anime.genres.take(8)) _Chip(g),
                          ],
                        ),
                      ],
                      if (anime.description != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          anime.description!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SectionHead(
                        title: 'Episodes',
                        trailing: state.status == DetailsStatus.loading
                            ? null
                            : '${state.episodes.length}',
                      ),
                      const SizedBox(height: 14),
                      if (state.status == DetailsStatus.loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (state.episodesError != null)
                        EmptyState(
                          icon: Icons.error_outline,
                          title: 'No episode list',
                          body: state.episodesError!,
                          tone: EmptyStateTone.problem,
                          primaryLabel: 'Try again',
                          primaryIcon: Icons.refresh,
                          onPrimary: () =>
                              context.read<DetailsCubit>().load(),
                        )
                      else if (state.episodes.isEmpty)
                        const EmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'No episodes',
                          body:
                              'The source listed none for this title. It may '
                              'not be available there.',
                        )
                      else
                        for (final e in state.episodes)
                          _EpisodeRow(anime: anime, episode: e),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.anime});
  final Anime anime;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      backgroundColor: AppColors.ground,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (anime.thumbnailUrl != null)
              Image.network(
                anime.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            // Functional scrim, not decoration: it buys text contrast over
            // artwork the app cannot predict (INSTRUCTIONS.md section 10).
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0xCC08090B),
                    AppColors.ground,
                  ],
                  stops: [0, 0.55, 1],
                ),
              ),
            ),
            Positioned(
              left: AppSpace.gutter,
              right: AppSpace.gutter,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    anime.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  if (anime.status != AnimeStatus.unknown ||
                      anime.author != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (anime.status != AnimeStatus.unknown)
                          anime.status.label,
                        if (anime.author != null) anime.author!,
                      ].join('  ·  '),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});
  final SourceRef source;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      border: Border.all(color: AppColors.outline),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.extension_outlined,
          size: 18,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SOURCE', style: AppText.kicker),
              const SizedBox(height: 4),
              Text(source.sourceName, style: AppText.body),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
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
          Icons.info_outline,
          size: 16,
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
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.anime, required this.episode});
  final Anime anime;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (episode.scanlator != null) episode.scanlator!,
      if (episode.uploadedAt != null) _date(episode.uploadedAt!),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () => context.push('/player', extra: (anime, episode)),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                episode.hasNumber
                    ? episode.number
                          .toStringAsFixed(episode.number % 1 == 0 ? 0 : 1)
                    : '–',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(fontSize: 14),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(meta, style: AppText.meta),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.play_circle_outline,
              size: 22,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
