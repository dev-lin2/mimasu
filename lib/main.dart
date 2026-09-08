import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'application/extensions/extensions_cubit.dart';
import 'core/di/locator.dart';
import 'core/theme/app_theme.dart';
import 'domain/repositories/extension_repository.dart';
import 'presentation/screens/extensions/extensions_screen.dart';
import 'presentation/screens/host_probe/host_probe_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const MimasuApp());
}

class MimasuApp extends StatelessWidget {
  const MimasuApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mimasu',
    debugShowCheckedModeBanner: false,
    theme: buildDarkTheme(),
    // Dark only: no light theme is designed (INSTRUCTIONS.md section 10).
    darkTheme: buildDarkTheme(),
    themeMode: ThemeMode.dark,
    home: const _Home(),
  );
}

/// Temporary shell. The bottom-nav shell of section 10 arrives with the rest
/// of Phase 1; until then the Extensions screen is the app, with the Phase 0
/// host probe reachable beside it.
class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ExtensionsCubit(locator<ExtensionRepository>()),
      child: Builder(
        builder: (context) => Stack(
          children: [
            const ExtensionsScreen(),
            Positioned(
              top: MediaQuery.of(context).padding.top + 6,
              right: 8,
              child: IconButton(
                tooltip: 'Extension host probe',
                icon: const Icon(
                  Icons.memory,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HostProbeScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
