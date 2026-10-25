// [File: lib/screens/main_screen.dart]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import screens
import '../config/routes.dart';
import '../presentation/screens/workout_home_screen.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'nutrition/nutrition_screen.dart';
import 'profile_screen.dart';

import 'home/tokens/saman_home_tokens.dart';
import 'home/widgets/saman_bottom_navigation_bar.dart';

import '../utils/auth_helper.dart';

// Import Provider
import '../providers/profile_provider.dart';

final mainNavIndexProvider = StateProvider<int>((ref) => 0);

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({
    super.key,
    this.onUnauthorizedLogout,
    this.loadProfileOnInit = true,
  });

  final VoidCallback? onUnauthorizedLogout;
  final bool loadProfileOnInit;

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  bool _isHandlingUnauthorized = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadProfileOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Validate this session without reusing pre-login state or requests.
        final profileNotifier = ref.read(profileProvider.notifier);
        profileNotifier.resetSession();
        profileNotifier.loadProfile();
      });
    }
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

    try {
      await AuthHelper.logout(ref);

      if (mounted) {
        if (widget.onUnauthorizedLogout != null) {
          widget.onUnauthorizedLogout!();
        } else {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint('[MAIN] Error in unauthorized logout: $e');
      if (mounted) {
        if (widget.onUnauthorizedLogout != null) {
          widget.onUnauthorizedLogout!();
        } else if (e is LogoutException &&
            (e.tokenState == AuthTokenState.confirmedLost ||
             e.tokenState == AuthTokenState.indeterminate)) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,
          );
        }
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
