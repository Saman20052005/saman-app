// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/profile/domain/entities/profile_entity.dart';
import '../providers/profile_provider.dart';
import '../config/app_translations.dart';
import '../config/app_theme.dart';
import '../config/theme_provider.dart';
import '../utils/auth_helper.dart';
import 'home/tokens/saman_home_tokens.dart';
import 'login/login_screen.dart';
import 'profile/edit_health_profile_screen.dart';
import 'profile/widgets/profile_widgets.dart';

/// Redesigned Profile Screen adhering strictly to the Calm Athleticism design system (Stitch export).
///
/// Contract Specifications:
/// - **Read-Only Personal Fitness Hub**: Displays athlete profile details and settings. Data state is
///   owned by existing Riverpod providers (`profileProvider`, `languageProvider`, `themeProvider`)
///   and [AuthHelper]. This widget makes no direct API requests itself.
/// - **Navigation**: Persistent bottom navigation bar is owned and rendered by `MainScreen`.
/// - **Edit / Complete Profile**: Interactive actions (e.g. Edit Profile button, complete profile banner,
///   and Health & Goals rows) navigate to the existing [EditHealthProfileScreen] edit flow. Missing backend
///   values display unavailable fallbacks (`—`, missing badges, or incomplete banner) without invented metrics.
/// - **Saman+ State**: [SamanPlusCard] displays the existing "Coming soon" state without an active purchase or checkout route.
///
/// Features composed Stitch components:
/// 1. [ProfileHeader] - Authoritative header with Settings shortcut
/// 2. [PersonalIdentityCard] - Athlete credentials, circular avatar, clean edit action
/// 3. Incomplete Profile Notice (when biometrics missing) with safe call-to-action
/// 4. [ProgressSnapshotCard] - Long-term consistency metrics (real/dash fallbacks)
/// 5. [SamanPlusCard] - Understated premium opportunity (Coming Soon)
/// 6. [ProfileSectionGroup] ("HEALTH & GOALS") - Real biometric data summaries
/// 7. [ProfileSectionGroup] ("PREFERENCES") - Language, theme, units, notification rows
/// 8. [ProfileSectionGroup] ("ACCOUNT & SUPPORT") - Account management & feedback rows
/// 9. [LogoutRow] - Quiet muted-red destructive action
/// 10. Generous scroll clearance (~140px) above MainScreen persistent navigation bar
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _userName = "User";
  String _email = "";

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final name = await AuthHelper.getUserName();
    final email = await AuthHelper.getUserEmail();
    if (!mounted) return;
    setState(() {
      _userName = name ?? "User";
      _email = email ?? "";
      if (_userName.isEmpty) _userName = "Athlete";
    });
  }

  String _tr(String key, {String? fallback}) {
    final locale = ref.read(languageProvider);
    final text = AppTranslations.text(key, locale);
    if (text == key && fallback != null) {
      return fallback;
    }
    return text;
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EditHealthProfileScreen(),
      ),
    );
  }

  void _showLanguageBottomSheet(ColorScheme colors) {
    final currentLocale = ref.read(languageProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: SamanHomeTokens.cardSurfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: SamanHomeTokens.cardSurfaceElevated,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SamanHomeTokens.spacingLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: SamanHomeTokens.borderHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: SamanHomeTokens.spacingLg),
                  Text(
                    _tr('language', fallback: 'Language'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.textWhite,
                    ),
                  ),
                  const SizedBox(height: SamanHomeTokens.spacingSm),
                  ListTile(
                    leading: const Text('🇬🇧', style: TextStyle(fontSize: 22)),
                    title: const Text(
                      'English',
                      style: TextStyle(color: SamanHomeTokens.textWhite),
                    ),
                    trailing: currentLocale.languageCode == 'en'
                        ? const Icon(Icons.check_circle, color: SamanHomeTokens.greenAccent)
                        : null,
                    onTap: () async {
                      await ref
                          .read(languageProvider.notifier)
                          .changeLanguage('en');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  ListTile(
                    leading: const Text('🇻🇳', style: TextStyle(fontSize: 22)),
                    title: const Text(
                      'Tiếng Việt',
                      style: TextStyle(color: SamanHomeTokens.textWhite),
                    ),
                    trailing: currentLocale.languageCode == 'vi'
                        ? const Icon(Icons.check_circle, color: SamanHomeTokens.greenAccent)
                        : null,
                    onTap: () async {
                      await ref
                          .read(languageProvider.notifier)
                          .changeLanguage('vi');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SamanHomeTokens.cardSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
          side: const BorderSide(color: SamanHomeTokens.border, width: 1),
        ),
        title: Text(
          _tr('logout', fallback: 'Log out'),
          style: const TextStyle(
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
            child: Text(
              _tr('cancel', fallback: 'Cancel'),
              style: const TextStyle(color: SamanHomeTokens.textSecondary),
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
            child: Text(_tr('logout', fallback: 'Log out')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AuthHelper.logout(ref);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  String _formatGoal(Goal? goal) {
    if (goal == null) return '—';
    switch (goal) {
      case Goal.lose_weight:
        return _tr('goal_lose_weight', fallback: 'Lose weight');
      case Goal.maintain_weight:
        return _tr('goal_maintain_weight', fallback: 'Maintain weight');
      case Goal.gain_muscle:
        return _tr('goal_build_muscle', fallback: 'Build muscle');
    }
  }

  String _formatActivityLevel(ActivityLevel? level) {
    if (level == null) return '—';
    switch (level) {
      case ActivityLevel.low:
        return _tr('activity_low', fallback: 'Low');
      case ActivityLevel.medium:
        return _tr('activity_medium', fallback: 'Moderate');
      case ActivityLevel.high:
        return _tr('activity_high', fallback: 'High');
    }
  }

  String _formatNutritionTargets(ProfileState state) {
    if (state.targetCalories <= 0 && state.targetProtein <= 0) {
      return '—';
    }
    final parts = <String>[];
    if (state.targetCalories > 0) {
      parts.add('${state.targetCalories} kcal');
    }
    if (state.targetProtein > 0) {
      parts.add('${state.targetProtein}g protein');
    }
    return parts.join(' · ');
  }

  Widget _buildBodyProfileValue(ProfileEntity profile) {
    final hasHeight = profile.height != null && profile.height! > 0;
    final hasWeight = profile.weight != null && profile.weight! > 0;
    final hasAge = profile.age != null && profile.age! > 0;

    if (!hasHeight && !hasWeight && !hasAge) {
      return const Text(
        '—',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: SamanHomeTokens.textSecondary,
        ),
      );
    }

    String? bmiString;
    if (hasHeight && hasWeight) {
      final h = profile.height! / 100.0;
      final bmi = profile.weight! / (h * h);
      bmiString = bmi.toStringAsFixed(1);
    }

    const textStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: SamanHomeTokens.textSecondary,
    );
    const dotStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: SamanHomeTokens.textMuted,
    );

    return Wrap(
      spacing: 5,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasAge) Text('${profile.age}', style: textStyle),
        if (hasAge && hasHeight) const Text('·', style: dotStyle),
        if (hasHeight) Text('${profile.height!.round()} cm', style: textStyle),
        if (hasHeight && hasWeight) const Text('·', style: dotStyle),
        if (hasWeight) Text('${profile.weight!.round()} kg', style: textStyle),
        if (bmiString != null) const Text('·', style: dotStyle),
        if (bmiString != null) Text('BMI $bmiString', style: textStyle),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLocale = ref.watch(languageProvider);
    final profileState = ref.watch(profileProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = profileState.profile;

    final goalText = profile.hasGoal ? _formatGoal(profile.rawGoal) : '—';
    final activityText = profile.hasActivityLevel
        ? _formatActivityLevel(profile.rawActivityLevel)
        : '—';
    final nutritionText = _formatNutritionTargets(profileState);
    final languageText =
        currentLocale.languageCode == 'vi' ? 'Tiếng Việt' : 'English';
    final appearanceText = isDark ? 'Dark Obsidian' : 'Light';

    final isIncomplete = !profileState.isProfileValid ||
        profileState.status == ProfileStatus.incomplete;

    return Scaffold(
      backgroundColor: SamanHomeTokens.canvas,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: SamanHomeTokens.spacingSm),

              // 1. Profile Header
              ProfileHeader(
                title: _tr('profile_title', fallback: 'Profile'),
                subtitle: _tr('profile_subtitle', fallback: 'Your health, progress & account'),
                onSettingsTap: () =>
                    _showLanguageBottomSheet(Theme.of(context).colorScheme),
              ),
              const SizedBox(height: SamanHomeTokens.spacingLg),

              // 2. Personal Identity Card
              PersonalIdentityCard(
                userName: _userName,
                userEmail: _email,
                planLabel: null, // Avoid fake metrics when absent from backend
                memberSince: null,
                onEditProfileTap: _navigateToEditProfile,
              ),

              // Incomplete Profile Banner (shown only when required biometrics are missing)
              if (isIncomplete) ...[
                const SizedBox(height: SamanHomeTokens.spacingLg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SamanHomeTokens.spacingLg,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
                    decoration: BoxDecoration(
                      color: SamanHomeTokens.cardSurface,
                      borderRadius:
                          BorderRadius.circular(SamanHomeTokens.radiusLg),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFEF4444),
                              size: 22,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Hồ sơ chưa hoàn thiện',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: SamanHomeTokens.textWhite,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Vui lòng cập nhật đầy đủ tuổi, chiều cao và cân nặng để cá nhân hóa lộ trình tập luyện.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: SamanHomeTokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: SamanHomeTokens.spacingMd),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            key: const Key('complete_profile_cta_button'),
                            onPressed: _navigateToEditProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SamanHomeTokens.greenAccent,
                              foregroundColor: const Color(0xFF003824),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    SamanHomeTokens.radiusMd),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Hoàn thiện hồ sơ',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: SamanHomeTokens.spacingLg),

              // 3. Your Progress
              // Long-term consistency snapshot; shows em-dash when backend source is absent
              const ProgressSnapshotCard(
                workoutsCount: null,
                streakDays: null,
                adherencePercent: null,
                onViewProgressTap: null, // No fake route
              ),
              const SizedBox(height: SamanHomeTokens.spacingLg),

              // 4. Saman+ Membership Card
              const SamanPlusCard(
                actionLabel: 'Coming soon',
                isComingSoon: true,
                onExploreTap: null,
              ),
              const SizedBox(height: SamanHomeTokens.spacingLg),

              // 5. Health & Goals Group
              ProfileSectionGroup(
                title: 'HEALTH & GOALS',
                children: [
                  ProfileNavRow(
                    icon: Icons.straighten_outlined,
                    title: 'Body profile',
                    valueWidget: _buildBodyProfileValue(profile),
                    isTwoLine: true,
                    showChevron: true,
                    onTap: _navigateToEditProfile,
                  ),
                  ProfileNavRow(
                    icon: Icons.flag_outlined,
                    title: 'Primary goal',
                    value: goalText,
                    showChevron: true,
                    onTap: _navigateToEditProfile,
                  ),
                  ProfileNavRow(
                    icon: Icons.bolt_outlined,
                    title: 'Activity level',
                    value: activityText,
                    showChevron: true,
                    onTap: _navigateToEditProfile,
                  ),
                  ProfileNavRow(
                    icon: Icons.restaurant_outlined,
                    title: 'Nutrition targets',
                    value: nutritionText,
                    isTwoLine: true,
                    showChevron: true,
                    onTap: _navigateToEditProfile,
                  ),
                  const ProfileNavRow(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Medical information',
                    valueWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: SamanHomeTokens.textSecondary,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Private',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: SamanHomeTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    showChevron: false,
                    onTap: null,
                  ),
                  const ProfileNavRow(
                    icon: Icons.photo_camera_outlined,
                    title: 'Measurements & photos',
                    value: 'Track body progress',
                    showChevron: false,
                    showDivider: false,
                    onTap: null,
                  ),
                ],
              ),
              const SizedBox(height: SamanHomeTokens.spacingLg),

              // 6. Preferences Group
              ProfileSectionGroup(
                title: 'PREFERENCES',
                children: [
                  ProfileNavRow(
                    icon: Icons.translate_outlined,
                    title: 'Language',
                    value: languageText,
                    showChevron: true,
                    onTap: () => _showLanguageBottomSheet(
                        Theme.of(context).colorScheme),
                  ),
                  const ProfileNavRow(
                    icon: Icons.tune_outlined,
                    title: 'Units',
                    value: 'Metric',
                    showChevron: false,
                    onTap: null,
                  ),
                  ProfileNavRow(
                    icon: isDark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    title: 'Appearance',
                    value: appearanceText,
                    showChevron: true,
                    onTap: () =>
                        ref.read(themeProvider.notifier).toggleTheme(),
                  ),
                  const ProfileNavRow(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    value: '—',
                    showChevron: false,
                    onTap: null,
                  ),
                  const ProfileNavRow(
                    icon: Icons.sync_alt_outlined,
                    title: 'Connected apps',
                    value: '—',
                    showChevron: false,
                    showDivider: false,
                    onTap: null,
                  ),
                ],
              ),
              const SizedBox(height: SamanHomeTokens.spacingLg),

              // 7. Account & Support Group
              const ProfileSectionGroup(
                title: 'ACCOUNT & SUPPORT',
                children: [
                  ProfileNavRow(
                    icon: Icons.card_membership_outlined,
                    title: 'Manage membership',
                    value: 'Coming soon',
                    showChevron: false,
                    onTap: null,
                  ),
                  ProfileNavRow(
                    icon: Icons.security_outlined,
                    title: 'Privacy & security',
                    showChevron: false,
                    onTap: null,
                  ),
                  ProfileNavRow(
                    icon: Icons.download_outlined,
                    title: 'Export data log',
                    showChevron: false,
                    onTap: null,
                  ),
                  ProfileNavRow(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & feedback',
                    showChevron: false,
                    onTap: null,
                  ),
                  ProfileNavRow(
                    icon: Icons.info_outline_rounded,
                    title: 'About Saman',
                    value: 'v3.8',
                    showChevron: false,
                    showDivider: false,
                    onTap: null,
                  ),
                ],
              ),
              const SizedBox(height: SamanHomeTokens.spacingLg),

              // 8. Logout Row
              LogoutRow(onTap: _logout),

              // 9. Generous scroll clearance above MainScreen persistent navigation bar
              const SizedBox(height: 140),
            ],
          ),
        ),
      ),
    );
  }
}
