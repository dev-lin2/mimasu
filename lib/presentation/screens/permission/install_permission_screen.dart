import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../extensions/host/host_api.g.dart';

/// The permission gate Phase 0 revealed was missing.
///
/// Declaring `REQUEST_INSTALL_PACKAGES` is not enough: the grant is per-app
/// and made by the user in system settings, and `canRequestPackageInstalls()`
/// is false until they do it (`docs/phase-0-findings.md` §5). Without this
/// screen the first install would fail with no explanation.
class InstallPermissionScreen extends StatefulWidget {
  const InstallPermissionScreen({super.key});

  @override
  State<InstallPermissionScreen> createState() =>
      _InstallPermissionScreenState();
}

class _InstallPermissionScreenState extends State<InstallPermissionScreen>
    with WidgetsBindingObserver {
  final _host = ExtensionHostApi();
  bool? _granted;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user grants this in system settings and comes back, so re-check on
    // resume rather than making them find a refresh button.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final granted = await _host.canInstallPackages();
      if (!mounted) return;
      setState(() {
        _granted = granted;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _granted = null;
        _checking = false;
      });
    }
  }

  Future<void> _open() async {
    final opened = await _host.openInstallPermissionSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open that settings page. Find Mimasu under '
            'Special app access, Install unknown apps.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted;

    return Scaffold(
      appBar: AppBar(title: const Text('Installing extensions')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          8,
          AppSpace.gutter,
          32,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpace.radiusCard),
              border: Border.all(
                color: granted == true
                    ? AppColors.ok.withValues(alpha: 0.4)
                    : AppColors.outline,
              ),
            ),
            child: Row(
              children: [
                if (_checking)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    granted == true
                        ? Icons.check_circle
                        : Icons.error_outline,
                    size: 18,
                    color: granted == true ? AppColors.ok : AppColors.accent,
                  ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    _checking
                        ? 'Checking…'
                        : granted == true
                        ? 'Allowed. Mimasu can install extensions.'
                        : granted == false
                        ? 'Not allowed yet. Extensions cannot install.'
                        : 'Could not read the current setting.',
                    style: AppText.body,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Extensions are separate Android apps, so Android — not Mimasu — '
            'installs them. That needs a one-time permission, granted per app '
            'in system settings.',
            style: AppText.bodySecondary,
          ),
          const SizedBox(height: 14),
          const Text(
            'You will still see the system installer for every extension, and '
            'you can revoke this at any time. Mimasu cannot install anything '
            'silently.',
            style: AppText.bodySecondary,
          ),
          const SizedBox(height: 22),
          if (granted != true)
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text(
                  'Open system settings',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.ground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpace.radiusCard),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
