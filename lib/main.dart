import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';

import 'application/browse/browse_cubit.dart';
import 'application/extensions/extensions_cubit.dart';
import 'core/di/locator.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/storage/app_prefs.dart';
import 'domain/repositories/content_source_repository.dart';
import 'domain/repositories/extension_manager.dart';
import 'domain/repositories/extension_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // libmpv has to be initialised before any Player is constructed.
  MediaKit.ensureInitialized();
  await configureDependencies();
  runApp(MimasuApp(prefs: locator<AppPrefs>()));
}

class MimasuApp extends StatelessWidget {
  const MimasuApp({required this.prefs, super.key});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    // One cubit above the router: Home and Settings both read the repository
    // count, and the Extensions screen is pushed from either, so its state
    // has to outlive any single route.
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ExtensionsCubit(
            locator<ExtensionRepository>(),
            locator<ExtensionManager>(),
          )..start(),
        ),
        BlocProvider(
          create: (_) => BrowseCubit(
            locator<ContentSourceRepository>(),
            locator<ExtensionManager>(),
          ),
        ),
      ],
      child: MaterialApp.router(
        title: 'Mimasu',
        debugShowCheckedModeBanner: false,
        theme: buildDarkTheme(),
        darkTheme: buildDarkTheme(),
        // Dark only; no light theme is designed (INSTRUCTIONS.md section 10).
        themeMode: ThemeMode.dark,
        routerConfig: buildRouter(prefs),
      ),
    );
  }
}
