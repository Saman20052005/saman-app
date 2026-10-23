// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/routes.dart';
import '../features/profile/domain/entities/onboarding_activity_choice.dart';
import '../features/profile/domain/entities/profile_entity.dart';
import '../providers/profile_provider.dart';
import '../utils/auth_helper.dart';
import 'home/tokens/saman_home_tokens.dart';
import 'profile/edit_health_profile_screen.dart';

/// Screen 06 — Profile & Telemetry Summary under Dark Calm Athleticism.
///
/// Features:
/// 1. Top Screen Header with atmospheric dark gym photography accent.
/// 2. Real athlete identity card with circular initials avatar and verified name.
/// 3. Read-only six-field summary:
///    - "Your goal" card with photographic accent and description
///    - "Your details" panel: Age, Gender, Height, Weight with exact decimals
///    - "Activity level" card with 5 canonical choices and fitness glyph
/// 4. Single 54px charcoal "Edit profile" action button.
/// 5. Restrained Account & "Log out" row with confirmation modal.
/// 6. Loading skeleton & non-destructive error recovery states.
/// 7. Zero vanity metrics, no BMI/BF/macros/subscription clutter, no inline form.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _userName = "User";

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final name = await AuthHelper.getUserName();
    if (!mounted) return;
    setState(() {
      _userName = (name != null && name.trim().isNotEmpty) ? name.trim() : "Athlete";
    });
  }

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'SA';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _formatDecimal(double? val) {
    if (val == null) return '—';
    if (val % 1 == 0) {
      return val.toInt().toString();
    }
    return val.toString();
  }

  String _formatGoalTitle(Goal? goal) {
    if (goal == null) return '—';
    switch (goal) {
      case Goal.lose_weight:
        return 'Lose weight';
      case Goal.maintain_weight:
        return 'Maintain weight';
      case Goal.gain_muscle:
        return 'Build muscle';
    }
  }

  String _formatGoalSubtitle(Goal? goal) {
    if (goal == null) return '';
    switch (goal) {
      case Goal.lose_weight:
        return 'Work toward a lower body weight.';
      case Goal.maintain_weight:
        return 'Keep your weight steady.';
      case Goal.gain_muscle:
        return 'Focus on building muscle.';
    }
  }

  String _formatGender(Gender? gender) {
    if (gender == null) return '—';
    switch (gender) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.other:
        return 'Other';
    }
  }

  String _formatActivityTitle(ProfileEntity profile) {
    final choice = OnboardingActivityChoice.fromApi(profile.rawActivityCanonical) ??
        OnboardingActivityChoice.fromLegacy(profile.rawActivityLevel);
    if (choice != null) {
      return choice.title;
    }
    return '—';
  }

  String _formatActivitySubtitle(ProfileEntity profile) {
    final choice = OnboardingActivityChoice.fromApi(profile.rawActivityCanonical) ??
        OnboardingActivityChoice.fromLegacy(profile.rawActivityLevel);
    if (choice != null) {
      return choice.subtitle;
    }
    return '';
  }

  String _goalAsset(Goal? goal) {
    switch (goal) {
      case Goal.lose_weight:
        return 'assets/profile/goal_lose_weight.jpg';
      case Goal.maintain_weight:
        return 'assets/profile/goal_maintain_weight.jpg';
      case Goal.gain_muscle:
      default:
        return 'assets/profile/goal_build_muscle.jpg';
    }
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EditHealthProfileScreen(),
      ),
    );
  }

  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SamanHomeTokens.cardSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
          side: const BorderSide(color: SamanHomeTokens.border, width: 1),
        ),
        title: const Text(
          'Log out',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: SamanHomeTokens.textWhite,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out of your Saman account?',
          style: TextStyle(
            fontSize: 14,
            color: SamanHomeTokens.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SamanHomeTokens.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
              ),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _isLoggingOut = true;
      try {
        await AuthHelper.logout(ref);
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,
          );
        }
      } catch (e) {
        _isLoggingOut = false;
        debugPrint('[AUTH] Logout failed: $e');
        if (mounted) {
          if (e is LogoutException &&
              (e.tokenState == AuthTokenState.confirmedLost ||
               e.tokenState == AuthTokenState.indeterminate)) {
            // Credentials lost or indeterminate: do not reopen protected UI on MainScreen.
            // Navigate away to Login and display explanatory warning SnackBar.
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.login,
              (route) => false,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đã đăng xuất (lỗi xóa dữ liệu phụ: $e)'),
                backgroundColor: const Color(0xFFF59E0B),
              ),
            );
          } else {
            // Token confirmed still intact: remain on screen and offer retry
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đăng xuất thất bại: $e'),
                backgroundColor: const Color(0xFFEF4444),
                action: SnackBarAction(
                  label: 'Thử lại',
                  textColor: Colors.white,
                  onPressed: _logout,
                ),
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final profile = profileState.profile;
    final isLoading = profileState.status == ProfileStatus.loading && !profile.isValid;
    final hasError = profileState.status == ProfileStatus.error && !profile.isValid;
    final isIncomplete = !profile.isValid || profileState.status == ProfileStatus.incomplete;

    final initials = _getInitials(_userName);

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D0E),
      body: Stack(
        children: [
          // Atmospheric Top-Right Photography Accent
          Positioned(
            top: 0,
            right: 0,
            width: 240,
            height: 220,
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/profile/step1_top_bg.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    opacity: const AlwaysStoppedAnimation(0.25),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF0C0D0E),
                          const Color(0xFF0C0D0E).withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xFF0C0D0E),
                          const Color(0xFF0C0D0E).withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

                  // 1. Screen Title
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Identity Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16171B).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF26282F), width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF212328),
                            border: Border.all(color: const Color(0xFF26282F), width: 1),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Your Saman profile',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Loading State (Skeleton)
                  if (isLoading) ...[
                    _buildLoadingSkeleton(),
                  ]
                  // Error State
                  else if (hasError) ...[
                    _buildErrorRecoveryCard(),
                  ]
                  // Telemetry Summary State
                  else ...[
                    // Incomplete profile notice
                    if (isIncomplete) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16171B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFEF4444), size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Hồ sơ chưa hoàn thiện',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 3. Your Goal Card
                    _buildYourGoalCard(profile),
                    const SizedBox(height: 14),

                    // 4. Your Details Panel (Age, Gender, Height, Weight)
                    _buildYourDetailsPanel(profile),
                    const SizedBox(height: 14),

                    // 5. Activity Level Card
                    _buildActivityLevelCard(profile),
                    const SizedBox(height: 14),

                    // 6. Full-Width Edit Profile Action
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        key: isIncomplete
                            ? const Key('complete_profile_cta_button')
                            : const Key('edit_profile_cta_button'),
                        onPressed: _navigateToEditProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16171B),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Color(0xFF26282F),
                              width: 1,
                            ),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: Color(0xFF9CA3AF),
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Edit profile',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 7. Account Section (Log out)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text(
                        'ACCOUNT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _logout,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16171B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF26282F),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                size: 20,
                                color: Color(0xFF9CA3AF),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Log out',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFF3F4F6),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Color(0xFF71717A),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 8. Generous scroll clearance above persistent tab bar
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYourGoalCard(ProfileEntity profile) {
    final title = _formatGoalTitle(profile.rawGoal);
    final subtitle = _formatGoalSubtitle(profile.rawGoal);
    final assetPath = _goalAsset(profile.rawGoal);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Right Photographic Accent (42% width)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 160,
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    assetPath,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    opacity: const AlwaysStoppedAnimation(0.40),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF16171B),
                          const Color(0xFF16171B).withOpacity(0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR GOAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYourDetailsPanel(ProfileEntity profile) {
    final ageText = profile.age != null ? '${profile.age}' : '—';
    final genderText = _formatGender(profile.rawGender);
    final heightText = profile.height != null
        ? '${_formatDecimal(profile.height)} cm'
        : '—';
    final weightText = profile.weight != null
        ? '${_formatDecimal(profile.weight)} kg'
        : '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOUR DETAILS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          _buildDetailRow('Age', ageText),
          _buildDivider(),
          _buildDetailRow('Gender', genderText),
          _buildDivider(),
          _buildDetailRow('Height', heightText),
          _buildDivider(),
          _buildDetailRow('Weight', weightText),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF3F4F6),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: const Color(0xFF26282F).withOpacity(0.7),
    );
  }

  Widget _buildActivityLevelCard(ProfileEntity profile) {
    final title = _formatActivityTitle(profile);
    final subtitle = _formatActivitySubtitle(profile);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ACTIVITY LEVEL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.fitness_center,
            size: 20,
            color: Color(0xFF9CA3AF),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 100,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF212328),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF212328).withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorRecoveryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFEF4444).withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "We couldn't load your profile. Please check connection and retry.",
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFF3F4F6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => ref.read(profileProvider.notifier).loadProfile(),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF212328),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFF26282F)),
              ),
            ),
            child: const Text('Try again ↺', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
