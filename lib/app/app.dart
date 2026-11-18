import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/app/app_gate.dart';
import 'package:bkdash_sanitary_ware/app/theme/app_theme.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:bkdash_sanitary_ware/features/settings/models/app_theme_mode.dart';
import 'package:bkdash_sanitary_ware/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

/// The root widget: theme, Arabic (right-to-left) localisation and the providers
/// that live as long as the app.
class BkdashApp extends StatelessWidget {
  const BkdashApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: dependencies),
        ChangeNotifierProvider<SettingsController>(
          create: (_) {
            final controller = SettingsController(dependencies.settings);
            controller.load();
            return controller;
          },
        ),
        ChangeNotifierProvider<SecurityController>(
          create: (_) {
            final controller = SecurityController(
              repository: dependencies.security,
              biometrics: dependencies.biometrics,
            );
            controller.initialize();
            return controller;
          },
        ),
      ],
      child: Selector<SettingsController, AppThemeMode>(
        selector: (_, settings) => settings.themeMode,
        builder: (context, themeMode, _) => MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode.toThemeMode(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AppGate(),
        ),
      ),
    );
  }
}

extension on AppThemeMode {
  ThemeMode toThemeMode() => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}
