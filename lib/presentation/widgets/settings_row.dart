import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Grouped settings rows, as designed. Deliberately not wrapped in individual
/// cards — the design uses group labels plus spacing, and boxing every row is
/// the habit that makes an interface look generic.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.label, required this.children, super.key});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppText.kicker),
      const SizedBox(height: 16),
      for (final child in children)
        Padding(padding: const EdgeInsets.only(bottom: 18), child: child),
    ],
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    this.summary,
    this.value,
    this.toggle,
    this.onToggle,
    this.onTap,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? summary;

  /// Shown on the right in accent, with a chevron. Mutually exclusive with
  /// [toggle].
  final String? value;

  final bool? toggle;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final value = this.value;
    final toggle = this.toggle;

    final row = Row(
      children: [
        Icon(
          icon,
          size: 19,
          color: enabled ? AppColors.textSecondary : AppColors.textTertiary,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.body.copyWith(
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
              if (summary != null) ...[
                const SizedBox(height: 3),
                Text(summary, style: AppText.meta),
              ],
            ],
          ),
        ),
        if (toggle != null)
          Switch(
            value: toggle,
            onChanged: enabled ? onToggle : null,
            activeThumbColor: AppColors.ground,
            activeTrackColor: AppColors.accent,
            inactiveThumbColor: AppColors.textSecondary,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
          )
        else if (value != null)
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.accent,
              ),
            ],
          )
        else
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textTertiary,
          ),
      ],
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      // Keeps the 48dp touch target from section 10 without visually
      // changing the row's spacing.
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
    );
  }
}
