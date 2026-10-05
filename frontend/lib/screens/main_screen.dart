// [File: lib/screens/main_screen.dart]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import screens
import '../presentation/screens/workout_home_screen.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'nutrition/nutrition_screen.dart';
import 'profile_screen.dart';

import 'home/tokens/saman_home_tokens.dart';
import 'home/widgets/saman_bottom_navigation_bar.dart';

import '../utils/auth_helper.dart';
import 'login/login_screen.dart';

// Import Provider
import '../providers/profile_provider.dart';

final mainNavIndexProvider = StateProvider<int>((ref) => 0);

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key, this.onUnauthorizedLogout});

  final VoidCallback? onUnauthorizedLogout;

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  bool _isHandlingUnauthorized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(profileProvider).status == ProfileStatus.unauthorized) {
        _handleUnauthorized();
      } else {
        ref.read(profileProvider.notifier).loadProfile();
      }
    });
  }

  Future<void> _handleUnauthorized() async {
    if (_isHandlingUnauthorized || !mounted) return;
    _isHandlingUnauthorized = true;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session expired. Please sign in again.'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );

    await AuthHelper.logout(ref);

    if (mounted) {
      if (widget.onUnauthorizedLogout != null) {
        widget.onUnauthorizedLogout!();
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  late final List<Widget> _screens = [
    HomeScreen(
      onOpenProfile: () => ref.read(mainNavIndexProvider.notifier).state = 4,
    ),
    const WorkoutHomeScreen(),
    const ChatScreen(),
    const NutritionScreen(), // Index 3 (shifted)
    const ProfileScreen(), // Index 4 (shifted)
  ];

  void _onTabTapped(int index) {
    // --- 🔥 PROFILE REDIRECT GUARD ---
    if (index == 3) {
      final profileState = ref.read(profileProvider);

      if (!profileState.isLoading && !profileState.isProfileValid) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("⚠️ Vui lòng cập nhật Hồ sơ sức khỏe để tính Calories!"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(mainNavIndexProvider.notifier).state = 4; // Chuyển sang Profile (shifted)
        return;
      }
    }

    ref.read(mainNavIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mainNavIndexProvider);

    ref.listen<ProfileState>(profileProvider, (previous, next) {
      if (next.status == ProfileStatus.unauthorized &&
          (previous == null || previous.status != ProfileStatus.unauthorized)) {
        _handleUnauthorized();
      }
    });

    return Scaffold(
      backgroundColor: SamanHomeTokens.canvas,
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: SamanBottomNavigationBar(
        currentIndex: currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}
