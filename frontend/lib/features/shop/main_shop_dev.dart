// Dedicated Dev Entrypoint for Saman Shop Remote Catalog Runtime Verification (CP-SHOP-07A)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_theme.dart';
import '../../config/routes.dart';
import '../../config/theme_provider.dart';
import '../../providers/profile_provider.dart';
import '../../utils/auth_helper.dart';
import 'presentation/providers/shop_providers.dart';
import 'presentation/screens/shop_landing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  const storage = FlutterSecureStorage();
  final sharedPrefs = await SharedPreferences.getInstance();
  await AuthHelper.printAuthStatus();

  const devBackendUrl = String.fromEnvironment(
    'SHOP_REMOTE_BASE_URL',
    defaultValue: 'http://10.0.2.2:8016',
  );

  runApp(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        shopLiveModeEnabledProvider.overrideWithValue(true),
        shopRemoteBaseUrlProvider.overrideWithValue(devBackendUrl),
      ],
      child: const ShopDevApp(),
    ),
  );
}

class ShopDevApp extends ConsumerWidget {
  const ShopDevApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Saman Shop Dev',
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.light(),
      darkTheme: SamanTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const ShopLandingScreen(),
      onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(settings),
    );
  }
}
