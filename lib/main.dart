import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/theme/veil_theme.dart';
import 'features/main/screens/splash_wrapper.dart';
import 'features/player/providers/player_settings_provider.dart';
import 'core/utils/crash_handler.dart';
import 'core/utils/method_channel_dispatcher.dart';
import 'diagnostics/diagnostic_service.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  CrashHandler.initialize();
  MethodChannelDispatcher.initialize();
  MediaKit.ensureInitialized();
  await DiagnosticService.instance.initialize();

  runApp(
    const ProviderScope(
      child: VeilApp(),
    ),
  );
}

class VeilApp extends ConsumerWidget {
  const VeilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playerSettingsProvider);
    final accentColor = VeilTheme.getAccentColor(settings.themeAccent);

    ThemeMode themeMode;
    switch (settings.themeMode) {
      case 'Light':
        themeMode = ThemeMode.light;
        break;
      case 'System':
        themeMode = ThemeMode.system;
        break;
      case 'Dark':
      default:
        themeMode = ThemeMode.dark;
        break;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: VeilTheme(
        accentColor: accentColor,
        amoledPureBlack: settings.amoledPureBlack,
        brightness: Brightness.light,
      ).themeData,
      darkTheme: VeilTheme(
        accentColor: accentColor,
        amoledPureBlack: settings.amoledPureBlack,
        brightness: Brightness.dark,
      ).themeData,
      themeMode: themeMode,
      home: const SplashWrapper(),
    );
  }
}