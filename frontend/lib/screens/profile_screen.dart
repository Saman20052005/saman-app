// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/auth_helper.dart';

import '../providers/profile_provider.dart';
import '../config/app_translations.dart';
import '../config/app_theme.dart';
import '../config/theme_provider.dart';
import 'login/login_screen.dart';
import 'profile/edit_health_profile_screen.dart';

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
      if (_userName.isEmpty) _userName = "Fitness Member";
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
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _tr('language'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ListTile(
                    leading: const Text('🇬🇧', style: TextStyle(fontSize: 24)),
                    title: const Text('English'),
                    trailing: currentLocale.languageCode == 'en'
                        ? Icon(Icons.check_circle, color: colors.primary)
                        : null,
                    onTap: () async {
                      await ref
                          .read(languageProvider.notifier)
                          .changeLanguage('en');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  ListTile(
                    leading: const Text('🇻🇳', style: TextStyle(fontSize: 24)),
                    title: const Text('Tiếng Việt'),
                    trailing: currentLocale.languageCode == 'vi'
                        ? Icon(Icons.check_circle, color: colors.primary)
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
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          _tr('logout'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _tr('cancel'),
              style: TextStyle(color: colors.secondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onPrimary,
            ),
            child: Text(_tr('logout')),
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

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    final profileState = ref.watch(profileProvider);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final profile = profileState.profile;
    final isValid = profileState.isProfileValid;

    String bmiText = "BMI: --";
    if (isValid && profile.height != null && profile.weight != null) {
      final h = profile.height! / 100;
      final w = profile.weight!;
      final bmi = w / (h * h);
      bmiText = "BMI: ${bmi.toStringAsFixed(1)}";
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: colors.onSurface),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          _tr('profile_title', fallback: 'Profile'),
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.dark_mode : Icons.light_mode,
              color: colors.onSurface,
            ),
            onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // User Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                110,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.lg),
                ),
                border: Border(bottom: BorderSide(color: colors.outline)),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: context.trackColor,
                    foregroundColor: colors.primary,
                    child: Text(
                      _userName.isNotEmpty ? _userName[0].toUpperCase() : "U",
                      style: textTheme.displayLarge?.copyWith(
                        fontSize: 36,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _userName,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "$_email • $bmiText",
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.secondary,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Health Profile Status Banner / Card
                  if (!isValid)
                    _IncompleteProfileCard(
                      onCompleteTap: _navigateToEditProfile,
                    )
                  else ...[
                    _ProfileSectionTitle(
                      title: _tr('body_stats'),
                      icon: Icons.accessibility_new,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ReadOnlyStatsRow(
                      age: profile.age?.toString() ?? '--',
                      height: profile.height != null
                          ? '${profile.height! % 1 == 0 ? profile.height!.toInt() : profile.height} cm'
                          : '--',
                      weight: profile.weight != null
                          ? '${profile.weight! % 1 == 0 ? profile.weight!.toInt() : profile.weight} kg'
                          : '--',
                      ageLabel: _tr('age'),
                      heightLabel: _tr('height'),
                      weightLabel: _tr('weight'),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    _ProfileSectionTitle(
                      title: _tr('goal_lifestyle'),
                      icon: Icons.flag,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ReadOnlyLifestyleCard(
                      goalLabel: profile.hasGoal ? _tr(profile.goal.name) : '-',
                      activityLabel: profile.hasActivityLevel ? _tr(profile.activityLevel.name) : '-',
                      genderLabel: profile.hasGender ? _tr(profile.gender.name) : '-',
                      goalTitle: _tr('main_goal'),
                      activityTitle: _tr('activity_level'),
                      genderTitle: _tr('gender'),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // Edit Profile CTA
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        key: const Key('edit_profile_cta_button'),
                        onPressed: _navigateToEditProfile,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        label: Text(
                          _tr('edit_profile', fallback: 'Chỉnh sửa hồ sơ'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.primary,
                          side: BorderSide(color: colors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xxl),

                  // Settings Group
                  _ProfileSettingsCard(
                    onLanguageTap: () => _showLanguageBottomSheet(colors),
                    onLogoutTap: _logout,
                    languageLabel: _tr('language'),
                    logoutLabel: _tr('logout'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncompleteProfileCard extends StatelessWidget {
  const _IncompleteProfileCard({required this.onCompleteTap});

  final VoidCallback onCompleteTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.error.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.error, size: 28),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Hồ sơ chưa hoàn thiện',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Vui lòng cập nhật đầy đủ tuổi, chiều cao và cân nặng để hệ thống tính toán lượng calo chính xác.',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('complete_profile_cta_button'),
              onPressed: onCompleteTap,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text(
                'Hoàn thiện hồ sơ',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: AppSpacing.md),
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ReadOnlyStatsRow extends StatelessWidget {
  const _ReadOnlyStatsRow({
    required this.age,
    required this.height,
    required this.weight,
    required this.ageLabel,
    required this.heightLabel,
    required this.weightLabel,
  });

  final String age;
  final String height;
  final String weight;
  final String ageLabel;
  final String heightLabel;
  final String weightLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatDisplayCard(
            label: ageLabel,
            value: age,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatDisplayCard(
            label: heightLabel,
            value: height,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatDisplayCard(
            label: weightLabel,
            value: weight,
            isHighlight: true,
          ),
        ),
      ],
    );
  }
}

class _StatDisplayCard extends StatelessWidget {
  const _StatDisplayCard({
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  final String label;
  final String value;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bgColor = isHighlight ? colors.primary : context.surfaceColor;
    final textColor = isHighlight ? colors.onPrimary : colors.onSurface;
    final labelColor =
        isHighlight ? colors.onPrimary.withOpacity(0.7) : colors.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isHighlight ? colors.primary : colors.outline,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(color: labelColor),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyLifestyleCard extends StatelessWidget {
  const _ReadOnlyLifestyleCard({
    required this.goalLabel,
    required this.activityLabel,
    required this.genderLabel,
    required this.goalTitle,
    required this.activityTitle,
    required this.genderTitle,
  });

  final String goalLabel;
  final String activityLabel;
  final String genderLabel;
  final String goalTitle;
  final String activityTitle;
  final String genderTitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          _LifestyleRow(
            title: goalTitle,
            value: goalLabel,
            colors: colors,
            textTheme: textTheme,
          ),
          Divider(height: AppSpacing.lg, color: colors.outline),
          _LifestyleRow(
            title: activityTitle,
            value: activityLabel,
            colors: colors,
            textTheme: textTheme,
          ),
          Divider(height: AppSpacing.lg, color: colors.outline),
          _LifestyleRow(
            title: genderTitle,
            value: genderLabel,
            colors: colors,
            textTheme: textTheme,
          ),
        ],
      ),
    );
  }
}

class _LifestyleRow extends StatelessWidget {
  const _LifestyleRow({
    required this.title,
    required this.value,
    required this.colors,
    required this.textTheme,
  });

  final String title;
  final String value;
  final ColorScheme colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: textTheme.bodyMedium?.copyWith(color: colors.secondary),
        ),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ProfileSettingsCard extends StatelessWidget {
  const _ProfileSettingsCard({
    required this.onLanguageTap,
    required this.onLogoutTap,
    required this.languageLabel,
    required this.logoutLabel,
  });

  final VoidCallback onLanguageTap;
  final VoidCallback onLogoutTap;
  final String languageLabel;
  final String logoutLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(Icons.language, size: 20, color: colors.primary),
            ),
            title: Text(
              languageLabel,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: colors.secondary,
            ),
            onTap: onLanguageTap,
          ),
          Divider(height: 1, color: colors.outline),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(Icons.logout, size: 20, color: colors.error),
            ),
            title: Text(
              logoutLabel,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.error,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: colors.secondary,
            ),
            onTap: onLogoutTap,
          ),
        ],
      ),
    );
  }
}
