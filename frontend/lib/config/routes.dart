import 'package:flutter/material.dart';
// Import các màn hình chính
import '../screens/splash_screen.dart';
import '../screens/login/login_screen.dart';
import '../features/profile/presentation/profile_gate.dart';
import '../screens/settings/app_settings_screen.dart';

class AppRoutes {
  // 1. Định nghĩa Constants (Tránh gõ sai string)
  static const String splash = '/';
  static const String login = '/login';
  static const String main = '/main';
  static const String appSettings = '/settings';

  // 2. Hàm Generate Route tập trung
  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    bool enableSplashAnimations = true,
  }) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => SplashScreen(
            enableAnimations: enableSplashAnimations,
          ),
        );

      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case main:
        return MaterialPageRoute(builder: (_) => const ProfileGate());

      case appSettings:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AppSettingsScreen(),
        );

      // Mặc định: Trả về trang lỗi hoặc Login nếu không tìm thấy route
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Route not found!')),
          ),
        );
    }
  }
}
