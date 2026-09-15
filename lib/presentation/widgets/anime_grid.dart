import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/source/anime.dart';
import 'anime_card.dart';

/// A responsive grid of poster cards.
///
/// The cell height is computed rather than expressed as an aspect ratio. A
/// ratio has to be guessed against one screen width and silently overflows on
/// every other one, because the poster scales with the column but the two
/// lines of title underneath do not.
class AnimeGrid extends StatelessWidget {
  const AnimeGrid({
    required this.items,
    required this.onTap,
    this.subtitleFor,
    this.onLongPress,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.gutter,
      0,
      AppSpace.gutter,
      32,
    ),
    super.key,
  });

  final List<Anime> items;
  final void Function(Anime) onTap;
  final String? Function(Anime)? subtitleFor;
  final void Function(Anime)? onLongPress;
  final EdgeInsets padding;

  /// Widest a column is allowed to get before another one is added.
  static const _targetColumn = 150.0;

  /// Title (two lines at 13/1.3), its gap, and the subtitle line below it.
  static const _captionHeight = 60.0;

  /// Posters are 2:3.
  static const _posterRatio = 3 / 2;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      final available = constraints.maxWidth - padding.horizontal;
      final columns = (available / _targetColumn).ceil().clamp(2, 6);
      final cell = (available - spacing * (columns - 1)) / columns;

      return GridView.builder(
        padding: padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: 16,
          mainAxisExtent: cell * _posterRatio + _captionHeight,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final anime = items[i];
          return AnimeCard(
            anime: anime,
            subtitle: subtitleFor?.call(anime),
            onTap: () => onTap(anime),
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(anime),
          );
        },
      );
    },
  );
}
