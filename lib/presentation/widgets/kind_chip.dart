import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum KindChipTone { ok, dim, warn }

/// The small format badge from the Extensions screen design. Every extension
/// carries one, so a future source kind slots in without reworking the row
/// (INSTRUCTIONS.md section 6.4).
class KindChip extends StatelessWidget {
  const KindChip({required this.label, this.tone = KindChipTone.ok, super.key});

  final String label;
  final KindChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      KindChipTone.ok => (
        AppColors.ok.withValues(alpha: 0.12),
        AppColors.ok,
      ),
      KindChipTone.warn => (
        AppColors.accent.withValues(alpha: 0.12),
        AppColors.accent,
      ),
      KindChipTone.dim => (
        Colors.white.withValues(alpha: 0.06),
        AppColors.textTertiary,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
