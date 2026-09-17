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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outline, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: colors.surface,
          elevation: 0,
          selectedItemColor: colors.primary,
          unselectedItemColor: colors.onSurface.withOpacity(0.6),
          selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12, height: 1.5),
          unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 12, height: 1.5),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.fitness_center_outlined),
              activeIcon: Icon(Icons.fitness_center_rounded),
              label: 'Workout',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: 'AI Coach',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.pie_chart_outline_rounded),
              activeIcon: Icon(Icons.pie_chart_rounded),
              label: 'Nutrition',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
