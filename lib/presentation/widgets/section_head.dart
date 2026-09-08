import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Section header with an optional right-hand count, as used throughout
/// `docs/design.pen`.
class SectionHead extends StatelessWidget {
  const SectionHead({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) Text(trailing, style: AppText.meta),
      ],
    );
  }
}
