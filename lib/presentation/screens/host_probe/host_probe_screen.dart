import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../extensions/host/host_api.g.dart';

/// Phase 0 diagnostic (INSTRUCTIONS.md section 14).
///
/// Reports what installed packages actually declare, asserting nothing about
/// feature names or metadata keys — those are marked VERIFY in section 5.3 and
/// this is how they get answered. Delete once Phase 0 closes.
class HostProbeScreen extends StatefulWidget {
  const HostProbeScreen({super.key});

  @override
  State<HostProbeScreen> createState() => _HostProbeScreenState();
}

class _HostProbeScreenState extends State<HostProbeScreen> {
  final _host = ExtensionHostApi();

  HostInfo? _info;
  List<ExtensionCandidate?> _candidates = const [];
  List<ClassProbeResult?> _probes = const [];
  String? _error;
  bool _busy = false;

  static const _needles = <String?>[
    'tachiyomi',
    'aniyomi',
    'mihon',
    'extension',
  ];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _host.getHostInfo();
      final found = await _host.scanForExtensions(_needles);

      // Source classes are declared in a metadata key ending `.class`, e.g.
      // `tachiyomi.extension.class`, semicolon-separated. Confirmed against
      // real extensions; do not go back to scraping every metadata value —
      // that picked up the lib version ("1.6") as a class name.
      final probes = <ClassProbeResult?>[];
      for (final c in found) {
        if (c == null) continue;
        final classNames = c.metadata.entries
            .where((e) => (e.key ?? '').endsWith('.class'))
            .map((e) => e.value ?? '')
            .expand((v) => v.split(';'))
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList();
        if (classNames.isEmpty) continue;
        probes.addAll(
          await _host.probeClasses(c.packageName, classNames.cast<String?>()),
        );
      }

      if (!mounted) return;
      setState(() {
        _info = info;
        _candidates = found;
        _probes = probes;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Extension host probe')),
      body: RefreshIndicator(
        onRefresh: _run,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'Pull to re-run. Nothing here assumes a feature name — it '
              'reports what installed packages actually declare.',
              style: AppText.bodySecondary,
            ),
            const SizedBox(height: 18),
            if (_busy) const _Card(title: 'Running…', rows: []),
            if (_error != null)
              _Card(
                title: 'Channel error',
                accentTitle: true,
                rows: [('error', _error!)],
              ),
            if (_info case final info?) ...[
              _Card(
                title: 'Channel round-trip',
                ok: true,
                rows: [
                  ('android', '${info.androidRelease} (API ${info.sdkInt})'),
                  ('host package', info.hostPackage),
                  (
                    'can install packages',
                    info.canRequestPackageInstalls
                        ? 'yes'
                        : 'no — must be granted',
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            _Card(
              title: 'Extension candidates',
              rows: [('found', '${_candidates.length}')],
            ),
            for (final c in _candidates.whereType<ExtensionCandidate>()) ...[
              const SizedBox(height: 14),
              _Card(
                title: c.label,
                rows: [
                  ('package', c.packageName),
                  ('version', '${c.versionName} (${c.versionCode})'),
                  ('apk', c.apkPath),
                  ('features', c.features.whereType<String>().join('\n')),
                  (
                    'metadata',
                    c.metadata.entries
                        .map((e) => '${e.key} = ${e.value}')
                        .join('\n'),
                  ),
                  ('sha-256', c.signatureSha256),
                ],
              ),
            ],
            if (_probes.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Card(
                title: 'Class probes',
                rows: [
                  for (final p in _probes.whereType<ClassProbeResult>())
                    (
                      p.className.split('.').last,
                      [
                        'loaded: ${p.loaded}',
                        'instantiated: ${p.instantiated}',
                        if (p.superclasses.isNotEmpty)
                          'ancestry:\n  '
                              '${p.superclasses.whereType<String>().join('\n  ')}',
                        if (p.error != null) 'error: ${p.error}',
                      ].join('\n'),
                    ),
                ],
              ),
            ],
            if (!_busy && _candidates.isEmpty && _error == null) ...[
              const SizedBox(height: 14),
              const _Card(
                title: 'No extensions installed',
                rows: [
                  (
                    'next',
                    'Install any Tachiyomi-family extension APK on this '
                        'device, then pull to refresh. Discovery, metadata, '
                        'signature and class loading are identical for manga '
                        'and anime extensions — only the final source '
                        'interface differs.',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.rows,
    this.ok = false,
    this.accentTitle = false,
  });

  final String title;
  final List<(String, String)> rows;
  final bool ok;
  final bool accentTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (ok)
                const Padding(
                  padding: EdgeInsets.only(right: 7),
                  child: Icon(Icons.check_circle, size: 15, color: AppColors.ok),
                ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accentTitle
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final (k, v) in rows) ...[
            const SizedBox(height: 10),
            Text(k.toUpperCase(), style: AppText.kicker),
            const SizedBox(height: 3),
            Text(
              v.isEmpty ? '—' : v,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
