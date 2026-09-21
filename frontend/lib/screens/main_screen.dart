// [File: lib/screens/main_screen.dart]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import screens
import '../presentation/screens/workout_home_screen.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
// import 'food_log_screen.dart'; // Bỏ dòng này nếu không dùng trực tiếp
import 'nutrition/nutrition_screen.dart';
import 'profile_screen.dart';

import 'home/tokens/saman_home_tokens.dart';
import 'home/widgets/saman_bottom_navigation_bar.dart';

// Import Provider
import '../providers/profile_provider.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;

  // FIX: Bỏ từ khóa 'const' ở đây để tránh lỗi nếu các màn hình con không phải hằng số
  final List<Widget> _screens = [
    const HomeScreen(),
    const WorkoutHomeScreen(),
    const ChatScreen(),
    const NutritionScreen(), // Index 3 (shifted)
    const ProfileScreen(), // Index 4 (shifted)
  ];

  void _onTabTapped(int index) {
    // --- 🔥 PROFILE REDIRECT GUARD ---
    if (index == 3) {
      final profileState = ref.read(profileProvider);

      if (!profileState.isProfileValid) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("⚠️ Vui lòng cập nhật Hồ sơ sức khỏe để tính Calories!"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _currentIndex = 4); // Chuyển sang Profile (shifted)
        return;
      }
    }

    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SamanHomeTokens.canvas,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: SamanBottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}
