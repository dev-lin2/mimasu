import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../application/browse/browse_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/source/anime.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_head.dart';

/// Home: the shelves of whichever source is selected.
///
/// Everything here comes from an installed extension — there is no catalogue
/// underneath (INSTRUCTIONS.md §1), so with no source there is genuinely
/// nothing to show, and the empty state says why.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<BrowseCubit>().start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Extensions are installed in Android's UI, so coming back is the moment
    // a new source might exist.
    if (state == AppLifecycleState.resumed) {
      context.read<BrowseCubit>().refreshSources();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BrowseCubit, BrowseState>(
      builder: (context, state) {
        final cubit = context.read<BrowseCubit>();
        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.surfaceRaised,
              onRefresh: () async {
                final source = state.selected;
                if (source != null) await cubit.load(source);
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  const _Header(),
                  if (state.sources.isNotEmpty) ...[
                    _SourceSwitcher(
                      sources: state.sources,
                      selected: state.selected,
                      onSelect: cubit.select,
                    ),
                    const SizedBox(height: 22),
                  ],
                  if (state.status == BrowseStatus.noSource)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpace.gutter,
                      ),
                      child: _NoSource(),
                    )
                  else if (state.status == BrowseStatus.loading)
                    const _ShelfSkeleton()
                  else if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.gutter,
                      ),
                      child: EmptyState(
                        icon: Icons.error_outline,
                        title: 'That source did not answer',
                        body: state.error!,
                        tone: EmptyStateTone.problem,
                        primaryLabel: 'Try again',
                        primaryIcon: Icons.refresh,
                        onPrimary: () {
                          final source = state.selected;
                          if (source != null) cubit.load(source);
                        },
                        secondaryLabel: 'Manage extensions',
                        onSecondary: () => context.push('/extensions'),
                      ),
                    )
                  else ...[
                    if (state.popular.isNotEmpty)
                      _Shelf(title: 'Popular', items: state.popular),
                    if (state.latest.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      _Shelf(title: 'Latest', items: state.latest),
                    ],
                    if (!state.hasAnything)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpace.gutter,
                        ),
                        child: EmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'Nothing to show',
                          body:
                              'This source answered, but returned no titles. '
                              'It may be having trouble, or need updating.',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpace.gutter, 4, 8, 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Mimasu', style: AppText.screenTitle),
        Row(
          children: [
            IconButton(
              tooltip: 'Downloads',
              onPressed: () => context.push('/downloads'),
              icon: const Icon(
                Icons.download_outlined,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ),
            IconButton(
              tooltip: 'Extensions',
              onPressed: () => context.push('/extensions'),
              icon: const Icon(
                Icons.extension_outlined,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SourceSwitcher extends StatelessWidget {
  const _SourceSwitcher({
    required this.sources,
    required this.selected,
    required this.onSelect,
  });

  final List<SourceRef> sources;
  final SourceRef? selected;
  final void Function(SourceRef) onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
    child: Row(
      children: [
        for (final source in sources)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => onSelect(source),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: source == selected
                      ? AppColors.surfaceRaised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: source == selected
                        ? AppColors.accent
                        : AppColors.outline,
                  ),
                ),
                child: Text(
                  source.sourceName,
                  style: TextStyle(
                    color: source == selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, required this.items});

  final String title;
  final List<Anime> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        child: SectionHead(title: title, trailing: '${items.length}'),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 240,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) => AnimeCard(
            anime: items[i],
            width: 124,
            onTap: () => context.push('/details', extra: items[i]),
          ),
        ),
      ),
    ],
  );
}

class _ShelfSkeleton extends StatelessWidget {
  const _ShelfSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 110,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 124,
                  height: 186,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(
                      AppSpace.radiusPoster,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _NoSource extends StatelessWidget {
  const _NoSource();

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.extension_outlined,
    title: 'Nothing to browse yet',
    body:
        'Mimasu plays what you bring to it. Add a repository, install a '
        'source, and its titles appear here.',
    primaryLabel: 'Add a source',
    primaryIcon: Icons.add,
    onPrimary: () => context.push('/extensions'),
    secondaryLabel: 'How sources work',
    onSecondary: () => context.push('/help/add-source'),
  );
}
