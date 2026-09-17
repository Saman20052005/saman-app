import 'package:flutter/material.dart';
// Import các màn hình chính
import '../screens/splash_screen.dart'; // Đảm bảo bạn có file này (hoặc thay bằng Login nếu chưa có)
import '../screens/login/login_screen.dart';
import '../screens/main_screen.dart';

class AppRoutes {
  // 1. Định nghĩa Constants (Tránh gõ sai string)
  static const String splash = '/';
  static const String login = '/login';
  static const String main = '/main';

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
        return MaterialPageRoute(builder: (_) => const MainScreen());

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
