import 'package:flutter/material.dart';

import 'extensions/host/host_api.g.dart';

void main() => runApp(const SpikeApp());

/// Palette from docs/design.pen (INSTRUCTIONS.md section 10). Hardcoded here
/// only because this is the Phase 0 spike; Phase 1 lifts these into
/// core/theme as a real ColorScheme.
const _ground = Color(0xFF08090B);
const _surface = Color(0xFF121418);
const _surfaceRaised = Color(0xFF1A1D23);
const _outline = Color(0xFF2A2E36);
const _textPrimary = Color(0xFFF2F3F5);
const _textSecondary = Color(0xFF9BA1AC);
const _textTertiary = Color(0xFF6B7280);
const _accent = Color(0xFFFF5E5B);
const _ok = Color(0xFF5FBF8F);

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mimasu — Phase 0',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _ground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
      ).copyWith(surface: _surface),
    ),
    home: const ProbePage(),
  );
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  final _host = ExtensionHostApi();

  HostInfo? _info;
  List<ExtensionCandidate?> _candidates = const [];
  List<ClassProbeResult?> _probes = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// Deliberately broad needles: we are discovering the real feature name and
  /// metadata keys, not asserting them (INSTRUCTIONS.md 5.3 VERIFY).
  static const _needles = <String?>[
    'tachiyomi',
    'aniyomi',
    'mihon',
    'extension',
  ];

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _host.getHostInfo();
      final found = await _host.scanForExtensions(_needles);

      // For each candidate, probe whatever class names its own metadata
      // advertises. Extensions list their source classes in a metadata value.
      final probes = <ClassProbeResult?>[];
      for (final c in found) {
        if (c == null) continue;
        final classNames = c.metadata.values
            .whereType<String>()
            .where((v) => v.contains('.') && !v.contains(' '))
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
      body: SafeArea(
        child: RefreshIndicator(
          color: _accent,
          backgroundColor: _surfaceRaised,
          onRefresh: _run,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              const Text(
                'Phase 0 — Extension host probe',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pull to re-run. Nothing here assumes a feature name — it '
                'reports what installed packages actually declare.',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
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
                      info.canRequestPackageInstalls ? 'yes' : 'no — must be granted',
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
                            'ancestry:\n  ${p.superclasses.whereType<String>().join('\n  ')}',
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
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (ok)
                const Padding(
                  padding: EdgeInsets.only(right: 7),
                  child: Icon(Icons.check_circle, size: 15, color: _ok),
                ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accentTitle ? _accent : _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final (k, v) in rows) ...[
            const SizedBox(height: 10),
            Text(
              k.toUpperCase(),
              style: const TextStyle(
                color: _textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              v.isEmpty ? '—' : v,
              style: const TextStyle(
                color: _textSecondary,
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
