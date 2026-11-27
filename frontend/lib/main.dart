// [File: lib/main.dart]
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_translations.dart';
import 'config/theme_provider.dart';
import 'config/routes.dart';
import 'config/app_theme.dart';
import 'core/services/client_error_reporter.dart';
import 'utils/auth_helper.dart';

import 'features/workout_cv/presentation/screens/workout_cv_screen.dart';

// Import Provider để load dữ liệu và truy cập sharedPreferencesProvider
import 'providers/profile_provider.dart';

void main() async {
  // ➕ Đổi thành async
  WidgetsFlutterBinding.ensureInitialized();
  ClientErrorReporter.installGlobalHandlers();

  // 1. Cấu hình UI System
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  // 2. Khởi tạo FlutterSecureStorage
  const storage = FlutterSecureStorage();

  final sharedPrefs = await SharedPreferences.getInstance();

  const isReplayTrial = bool.fromEnvironment('WORKOUT_CV_REPLAY_TRIAL');
  if (isReplayTrial) {
    debugPrint('NETWORK BYPASSED: Nhảy thẳng vào Lat Pulldown Replay');
  }

  // 2.1. Debug: Print auth status on startup
  if (!isReplayTrial) {
    await AuthHelper.printAuthStatus();
  }

  // 3. Chạy App với ProviderScope đã Override
  runApp(
    ProviderScope(
      overrides: [
        // 💉 Bơm dependency FlutterSecureStorage vào hệ thống Provider
        secureStorageProvider.overrideWithValue(storage),
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key, this.enableSplashAnimations = true});

  final bool enableSplashAnimations;

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(languageProvider);
    final themeMode = ref.watch(themeProvider);

    const isReplayTrial = bool.fromEnvironment('WORKOUT_CV_REPLAY_TRIAL');

    return MaterialApp(
      title: 'Saman',
      debugShowCheckedModeBanner: false,

      // Theme Config
      theme: SamanTheme.light(),
      darkTheme: SamanTheme.dark(),
      themeMode: themeMode,

      // Localization Config
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Routing
      home: isReplayTrial
          ? const WorkoutCvScreen(
              exerciseId: 'lat-pulldown',
              exerciseSlug: 'lat-pulldown',
              exerciseName: 'Lat Pulldown',
            )
          : null,
      initialRoute: isReplayTrial ? null : AppRoutes.splash,
      onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(
        settings,
        enableSplashAnimations: widget.enableSplashAnimations,
      ),
    );
  }
}
