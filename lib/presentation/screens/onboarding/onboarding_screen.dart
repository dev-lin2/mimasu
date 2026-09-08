import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/storage/app_prefs.dart';

/// Three-screen first run, as designed.
///
/// Leads with what the app does rather than what it lacks, but still makes
/// clear that a source is required before anything plays — otherwise a user
/// reaches a title and hits a dead end with no explanation
/// (INSTRUCTIONS.md section 10).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.prefs, super.key});

  final AppPrefs prefs;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _pages = [
    (
      Icons.play_circle_outline,
      'Everything you watch, in one place.',
      'Browse and search across the sources you install, save what you are '
          'watching, download episodes for offline, and play them with '
          'quality, audio-track and subtitle control.',
      <String>[],
    ),
    (
      Icons.extension_outlined,
      'You choose where it streams from.',
      'Everything playable comes from extensions you install yourself. '
          'Mimasu ships none, so you paste in a repository link you found and '
          'pick from what it offers.',
      <String>[
        'Extensions install as Android apps — you will see the system '
            'installer once per extension',
        'Mimasu checks each signing key and warns you when it does not '
            'recognise one',
        'Extensions run as real code with their own network access — only '
            'install ones you trust',
      ],
    ),
    (
      Icons.link,
      'Add a source to start watching.',
      'Paste a repository URL to install your first source. You can look '
          'around without one — a source is what lets you play episodes.\n\n'
          'Mimasu does not recommend repositories; what you add is your '
          'choice.',
      <String>[],
    ),
  ];

  Future<void> _finish({required bool goToExtensions}) async {
    await widget.prefs.setOnboardingSeen();
    if (!mounted) return;
    context.go(goToExtensions ? '/extensions' : '/home');
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final (icon, heading, body, bullets) = _pages[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 44, 24, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            icon,
                            color: AppColors.accent,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          heading,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          body,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                        if (bullets.isNotEmpty) const SizedBox(height: 24),
                        for (final b in bullets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 17,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Text(
                                    b,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3.5),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: i == _page ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? AppColors.accent
                                  : AppColors.outline,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: isLast
                          ? () => _finish(goToExtensions: true)
                          : () => _controller.nextPage(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOut,
                            ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.ground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpace.radiusCard,
                          ),
                        ),
                      ),
                      child: Text(
                        isLast ? 'Add a source' : 'Next',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _finish(goToExtensions: false),
                    child: Text(
                      isLast ? 'Not now — look around first' : 'Skip',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
