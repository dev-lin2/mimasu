import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../application/browse/browse_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/anime_grid.dart';
import '../../widgets/empty_state.dart';

/// Search queries the selected source directly — results come from it, not
/// from any catalogue Mimasu holds (INSTRUCTIONS.md §1).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BrowseCubit, BrowseState>(
      builder: (context, state) {
        final cubit = context.read<BrowseCubit>();
        final source = state.selected;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    4,
                    AppSpace.gutter,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Search', style: AppText.screenTitle),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        enabled: source != null,
                        autocorrect: false,
                        textInputAction: TextInputAction.search,
                        onSubmitted: cubit.search,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 17),
                                  color: AppColors.textTertiary,
                                  onPressed: () {
                                    _controller.clear();
                                    cubit.clearSearch();
                                    setState(() {});
                                  },
                                ),
                          hintText: source == null
                              ? 'Install a source to search'
                              : 'Search ${source.sourceName}',
                          hintStyle: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceRaised,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpace.radiusCard,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpace.radiusCard,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpace.radiusCard,
                            ),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body(context, state, cubit)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, BrowseState state, BrowseCubit cubit) {
    if (state.selected == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        child: EmptyState(
          icon: Icons.search_off,
          title: 'Search needs a source',
          body:
              'Results come from the sources you install, not from a '
              'catalogue Mimasu ships.',
        ),
      );
    }
    if (state.searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        child: EmptyState(
          icon: Icons.error_outline,
          title: 'Search failed',
          body: state.error!,
          tone: EmptyStateTone.problem,
          primaryLabel: 'Try again',
          primaryIcon: Icons.refresh,
          onPrimary: () => cubit.search(state.query),
        ),
      );
    }
    if (state.results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        child: EmptyState(
          icon: state.query.isEmpty ? Icons.search : Icons.search_off,
          title: state.query.isEmpty
              ? 'Search ${state.selected!.sourceName}'
              : 'Nothing matched “${state.query}”',
          body: state.query.isEmpty
              ? 'Type a title above. Only the selected source is searched.'
              : 'That source returned no results. Another source may have it.',
        ),
      );
    }

    return AnimeGrid(
      items: state.results,
      onTap: (anime) => context.push('/details', extra: anime),
    );
  }
}
