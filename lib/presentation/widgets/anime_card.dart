import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/source/anime.dart';

/// The poster card from `docs/design.pen`.
///
/// Thumbnails come from arbitrary sites and often need the source's headers,
/// which `Image.network` cannot send — so a failed load falls back to a tonal
/// placeholder rather than a broken-image glyph.
class AnimeCard extends StatelessWidget {
  const AnimeCard({
    required this.anime,
    required this.width,
    this.onTap,
    super.key,
  });

  final Anime anime;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = anime.thumbnailUrl;

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpace.radiusPoster),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpace.radiusPoster),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: thumb == null
                    ? _Placeholder(seed: anime.title)
                    : Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _Placeholder(seed: anime.title),
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : _Placeholder(seed: anime.title),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              anime.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (anime.status != AnimeStatus.unknown) ...[
              const SizedBox(height: 2),
              Text(anime.status.label, style: AppText.meta.copyWith(fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tonal stand-in, tinted from the title so a shelf does not look like a row
/// of identical grey rectangles.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.seed});
  final String seed;

  static const _pairs = [
    [Color(0xFF3B4F7A), Color(0xFF1B2233)],
    [Color(0xFF7A4A3B), Color(0xFF33211B)],
    [Color(0xFF2F6B5E), Color(0xFF16302A)],
    [Color(0xFF5B3B7A), Color(0xFF261B33)],
    [Color(0xFF7A6B3B), Color(0xFF332D1B)],
    [Color(0xFF3B6B7A), Color(0xFF1B2E33)],
  ];

  @override
  Widget build(BuildContext context) {
    final pair = _pairs[seed.hashCode.abs() % _pairs.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: pair,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: Colors.white.withValues(alpha: 0.22),
          size: 26,
        ),
      ),
    );
  }
}
