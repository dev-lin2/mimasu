import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The empty/error state card used across the designed screens
/// (`docs/design.pen`). Every list in the app needs loading, empty and error
/// states (INSTRUCTIONS.md section 10), and they all look like this.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.tone = EmptyStateTone.neutral,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final EmptyStateTone tone;

  @override
  Widget build(BuildContext context) {
    final border = tone == EmptyStateTone.problem
        ? AppColors.accent.withValues(alpha: 0.2)
        : AppColors.outline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 26),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(color: border),
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
            child: Icon(icon, color: AppColors.accent, size: 24),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(body, textAlign: TextAlign.center, style: AppText.bodySecondary),
          if (primaryLabel != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: onPrimary,
                icon: Icon(primaryIcon ?? Icons.add, size: 16),
                label: Text(
                  primaryLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.ground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onSecondary,
              child: Text(
                secondaryLabel!,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum EmptyStateTone { neutral, problem }
