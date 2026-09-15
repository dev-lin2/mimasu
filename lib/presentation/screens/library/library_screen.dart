import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../application/library/library_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/library/library_entry.dart';
import '../../widgets/anime_grid.dart';
import '../../widgets/empty_state.dart';

/// Library is local only — no account, no sync (INSTRUCTIONS.md §7).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryStatus _tab = LibraryStatus.watching;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final entries = state.forStatus(_tab);
        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    4,
                    AppSpace.gutter,
                    0,
                  ),
                  child: Text('Library', style: AppText.screenTitle),
                ),
                const SizedBox(height: 18),
                _Tabs(
                  selected: _tab,
                  countFor: state.countFor,
                  onSelect: (s) => setState(() => _tab = s),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: entries.isEmpty
                      ? _Empty(tab: _tab, anySaved: state.entries.isNotEmpty)
                      : _Grid(entries: entries, state: state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.countFor,
    required this.onSelect,
  });

  final LibraryStatus selected;
  final int Function(LibraryStatus) countFor;
  final ValueChanged<LibraryStatus> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
    child: Row(
      children: [
        for (var i = 0; i < LibraryStatus.values.length; i++) ...[
          _Tab(
            status: LibraryStatus.values[i],
            selected: LibraryStatus.values[i] == selected,
            count: countFor(LibraryStatus.values[i]),
            onTap: () => onSelect(LibraryStatus.values[i]),
          ),
          if (i != LibraryStatus.values.length - 1) const SizedBox(width: 22),
        ],
      ],
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.status,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final LibraryStatus status;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Column(
      children: [
        Text(
          count == 0 ? status.label : '${status.label}  $count',
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textTertiary,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: 22,
          height: 2,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    ),
  );
}

class _Grid extends StatelessWidget {
  const _Grid({required this.entries, required this.state});

  final List<LibraryEntry> entries;
  final LibraryState state;

  @override
  Widget build(BuildContext context) => AnimeGrid(
    items: [for (final e in entries) e.anime],
    // The source is not asked how many episodes exist — that would be a
    // network call per tile — so this counts what was watched rather than
    // showing a fraction it cannot complete.
    subtitleFor: (anime) {
      final watched = state.watchedCount(anime.id);
      return watched == 0 ? null : '$watched watched';
    },
    onTap: (anime) => context.push('/details', extra: anime),
    onLongPress: (anime) {
      final entry = state.entryFor(anime.id);
      if (entry != null) _showActions(context, entry);
    },
  );

  void _showActions(BuildContext context, LibraryEntry entry) {
    final cubit = context.read<LibraryCubit>();
    showModalBottomSheet<void>(
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                entry.anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final status in LibraryStatus.values)
              ListTile(
                dense: true,
                leading: Icon(
                  status == entry.status
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: status == entry.status
                      ? AppColors.accent
                      : AppColors.textTertiary,
                ),
                title: Text(status.label, style: AppText.body),
                onTap: () {
                  cubit.setStatus(entry.id, status);
                  Navigator.of(sheet).pop();
                },
              ),
            const Divider(height: 12, color: AppColors.outline),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.delete_outline,
                size: 19,
                color: AppColors.accent,
              ),
              title: Text(
                'Remove from library',
                style: AppText.body.copyWith(color: AppColors.accent),
              ),
              onTap: () {
                cubit.remove(entry.id);
                Navigator.of(sheet).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tab, required this.anySaved});

  final LibraryStatus tab;
  final bool anySaved;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
    // Nothing in *this* tab is a different situation from nothing at all, and
    // offering "add a source" to someone who already has a library is noise.
    child: anySaved
        ? EmptyState(
            icon: Icons.bookmark_outline,
            title: 'Nothing here',
            body:
                'No series are marked as ${tab.label.toLowerCase()}. '
                'Hold a cover in another tab to move it here.',
          )
        : EmptyState(
            icon: Icons.bookmark_outline,
            title: 'Nothing saved yet',
            body:
                'Series you save appear here, stored on this device only. '
                'A source has to be installed first.',
            primaryLabel: 'Add a source',
            primaryIcon: Icons.add,
            onPrimary: () => context.push('/extensions'),
          ),
  );
}
