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
import 'utils/auth_helper.dart';

// Import Provider để load dữ liệu và truy cập sharedPreferencesProvider
import 'providers/profile_provider.dart';

void main() async {
  // ➕ Đổi thành async
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Cấu hình UI System
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  // 2. Khởi tạo FlutterSecureStorage
  const storage = FlutterSecureStorage();

  final sharedPrefs = await SharedPreferences.getInstance();

  // 2.1. Debug: Print auth status on startup
  await AuthHelper.printAuthStatus();

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
  void initState() {
    super.initState();
    // Profile loading ownership is delegated to MainScreen upon entering authenticated session
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(languageProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Fitness & Nutrition',
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
      initialRoute: AppRoutes.splash,
      onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(
        settings,
        enableSplashAnimations: widget.enableSplashAnimations,
      ),
    );
  }
}
