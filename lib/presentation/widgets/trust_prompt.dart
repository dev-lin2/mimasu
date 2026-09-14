import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/extension/installed_extension.dart';

/// The untrusted-extension prompt from `docs/design.pen` (INSTRUCTIONS.md §5.5).
///
/// This is the honest counterpart to having no sandbox: there is no technical
/// guarantee to fall back on, so the decision has to be explicit and informed.
/// It states plainly that extensions run as real code with their own network
/// access, and shows the key so it can be compared.
Future<TrustDecision?> showTrustPrompt(
  BuildContext context,
  PendingInstall pending,
) => showDialog<TrustDecision>(
  context: context,
  barrierDismissible: true,
  builder: (context) => _TrustDialog(pending: pending),
);

enum TrustDecision { trustAndInstall, cancel }

class _TrustDialog extends StatelessWidget {
  const _TrustDialog({required this.pending});

  final PendingInstall pending;

  @override
  Widget build(BuildContext context) {
    final mismatch = pending.declaredKeyMatches == false;

    return Dialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.accent,
                size: 21,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Trust this extension?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${pending.label} is signed by a key Mimasu does not recognise. '
              'Extensions run as real Android code with their own network '
              'access — install it only if you trust where it came from.',
              style: AppText.bodySecondary,
            ),
            if (mismatch) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                // Worth shouting about: the file is not signed by the key the
                // repository said would sign it.
                child: const Text(
                  "This key does not match the one the repository declared. "
                  'The file may not have come from where the index says.',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _fact('Package', pending.packageName),
                  _fact('Version', pending.versionName),
                  _fact('Signing key', pending.shortKey),
                  _fact('Repository', _host(pending.repositoryUrl)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(TrustDecision.cancel),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.outline),
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(TrustDecision.trustAndInstall),
                    icon: const Icon(Icons.verified_user_outlined, size: 15),
                    label: const Text(
                      'Trust & install',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.ground,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _fact(String key, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(key, style: AppText.meta.copyWith(fontSize: 11)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;
}
