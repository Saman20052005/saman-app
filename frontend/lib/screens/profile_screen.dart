// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/auth_helper.dart';

// Import Feature Profile
import '../features/profile/domain/entities/profile_entity.dart';
import '../providers/profile_provider.dart';
import '../config/app_translations.dart';
import '../config/app_theme.dart';
import '../config/theme_provider.dart';
import 'login/login_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _allergiesController = TextEditingController();

  Gender _selectedGender = Gender.male;
  ActivityLevel _selectedActivity = ActivityLevel.medium;
  Goal _selectedGoal = Goal.maintain_weight;

  String _userName = "User";
  String _email = "";
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final name = await AuthHelper.getUserName();
    final email = await AuthHelper.getUserEmail();
    setState(() {
      _userName = name ?? "User";
      _email = email ?? "";
      if (_userName.isEmpty) _userName = "Fitness Member";
    });
  }

  String tr(String key) {
    final locale = ref.read(languageProvider);
    return AppTranslations.text(key, locale);
  }

  void _syncDataFromProvider(ProfileState state) {
    if (state.isProfileValid) {
      final p = state.profile;
      _ageController.text = p.age?.toString() ?? '';
      _heightController.text = p.height?.toString() ?? '';
      _weightController.text = p.weight?.toString() ?? '';
      _allergiesController.text = p.allergies.join(', ');

      setState(() {
        _selectedGender = p.gender;
        _selectedActivity = p.activityLevel;
        _selectedGoal = p.goal;
        _isInit = true;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final newProfile = ProfileEntity(
      age: int.tryParse(_ageController.text),
      height: double.tryParse(_heightController.text),
      weight: double.tryParse(_weightController.text),
      gender: _selectedGender,
      activityLevel: _selectedActivity,
      goal: _selectedGoal,
      allergies:
          _allergiesController.text.split(',').map((e) => e.trim()).toList(),
    );

    try {
      await ref.read(profileProvider.notifier).updateProfile(newProfile);
      final newState = ref.read(profileProvider);
      _showSnackBar("Đã lưu! Mục tiêu: ${newState.targetCalories} kcal");
    } catch (e) {
      _showSnackBar("Lỗi cập nhật: $e", isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: colors.onPrimary)),
        backgroundColor: isError ? colors.error : colors.primary,
        behavior: SnackBarBehavior.floating,
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
                    tr('language'),
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
                      if (mounted) Navigator.pop(ctx);
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
                      if (mounted) Navigator.pop(ctx);
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
        title:
            Text(tr('logout'), style: Theme.of(context).textTheme.titleMedium),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                Text(tr('cancel'), style: TextStyle(color: colors.secondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onPrimary,
            ),
            child: Text(tr('logout')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
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

    if (!_isInit && profileState.isProfileValid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncDataFromProvider(profileState);
      });
    }

    ref.listen<ProfileState>(profileProvider, (previous, next) {
      if (next.profile.isValid && !_isInit) _syncDataFromProvider(next);
    });

    return Scaffold(
      backgroundColor: context.bgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode,
                color: colors.onSurface),
            onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildHeader(profileState, colors, textTheme),
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
                    _buildSectionHeader(tr('body_stats'),
                        Icons.accessibility_new, colors, textTheme),
                    const SizedBox(height: AppSpacing.lg),
                    _buildStatsGrid(colors, textTheme),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildSectionHeader(
                        tr('goal_lifestyle'), Icons.flag, colors, textTheme),
                    const SizedBox(height: AppSpacing.lg),
                    _buildSelectionCard(
                        tr('main_goal'),
                        Goal.values,
                        _selectedGoal,
                        (val) => setState(() => _selectedGoal = val),
                        colors,
                        textTheme),
                    const SizedBox(height: AppSpacing.md),
                    _buildSelectionCard(
                        tr('activity_level'),
                        ActivityLevel.values,
                        _selectedActivity,
                        (val) => setState(() => _selectedActivity = val),
                        colors,
                        textTheme),
                    const SizedBox(height: AppSpacing.md),
                    _buildSelectionCard(
                        tr('gender'),
                        Gender.values,
                        _selectedGender,
                        (val) => setState(() => _selectedGender = val),
                        colors,
                        textTheme),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildSectionHeader(tr('medical_notes'),
                        Icons.medical_services_outlined, colors, textTheme),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _allergiesController,
                      style: TextStyle(color: colors.onSurface),
                      decoration: InputDecoration(
                        hintText: tr('allergies_hint'),
                        hintStyle: TextStyle(color: colors.secondary),
                        filled: true,
                        fillColor: context.surfaceColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildSettingsGroup(colors, textTheme),
                    const SizedBox(height: AppSpacing.xxl),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: profileState.isLoading ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md)),
                        ),
                        child: profileState.isLoading
                            ? CircularProgressIndicator(color: colors.onPrimary)
                            : Text(tr('save_changes'),
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      ProfileState state, ColorScheme colors, TextTheme textTheme) {
    String bmiText = "BMI: --";
    if (state.profile.isValid) {
      final h = state.profile.height! / 100;
      final w = state.profile.weight!;
      final bmi = w / (h * h);
      bmiText = "BMI: ${bmi.toStringAsFixed(1)}";
    }

    return Container(
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
              style: textTheme.displayLarge
                  ?.copyWith(fontSize: 36, color: colors.onSurface),
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
            style: textTheme.bodyMedium?.copyWith(color: colors.secondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(ColorScheme colors, TextTheme textTheme) {
    return Row(
      children: [
        Expanded(
            child: _buildStatCard(
                tr('age'), _ageController, "", colors, textTheme)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
            child: _buildStatCard(
                tr('height'), _heightController, "cm", colors, textTheme)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
            child: _buildStatCard(
                tr('weight'), _weightController, "kg", colors, textTheme,
                isHighlight: true)),
      ],
    );
  }

  Widget _buildStatCard(String label, TextEditingController controller,
      String suffix, ColorScheme colors, TextTheme textTheme,
      {bool isHighlight = false}) {
    final bgColor = isHighlight ? colors.primary : colors.surface;
    final textColor = isHighlight ? colors.onPrimary : colors.onSurface;
    final labelColor =
        isHighlight ? colors.onPrimary.withOpacity(0.7) : colors.secondary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isHighlight ? colors.primary : colors.outline,
        ),
      ),
      child: Column(
        children: [
          Text(label, style: textTheme.labelSmall?.copyWith(color: labelColor)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: SizedBox(
                  width: 45,
                  child: TextFormField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                    decoration: const InputDecoration.collapsed(hintText: '0'),
                  ),
                ),
              ),
              if (suffix.isNotEmpty)
                Text(suffix,
                    style: textTheme.bodySmall?.copyWith(color: labelColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, ColorScheme colors, TextTheme textTheme) {
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

  Widget _buildSelectionCard<T extends Enum>(
      String title,
      List<T> options,
      T currentVal,
      Function(T) onSelect,
      ColorScheme colors,
      TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((option) {
                final isSelected = currentVal == option;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => onSelect(option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? colors.primary : context.trackColor,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: isSelected ? colors.primary : colors.outline,
                        ),
                      ),
                      child: Text(
                        option.name.toUpperCase().replaceAll('_', ' '),
                        style: textTheme.labelMedium?.copyWith(
                          color:
                              isSelected ? colors.onPrimary : colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(ColorScheme colors, TextTheme textTheme) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          _buildSettingsItem(Icons.language, tr('language'),
              () => _showLanguageBottomSheet(colors), colors, textTheme),
          Divider(height: 1, color: colors.outline),
          _buildSettingsItem(
              Icons.logout, tr('logout'), _logout, colors, textTheme,
              isDestructive: true),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(IconData icon, String title, VoidCallback onTap,
      ColorScheme colors, TextTheme textTheme,
      {bool isDestructive = false}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isDestructive
              ? colors.error.withOpacity(0.1)
              : colors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isDestructive ? colors.error : colors.primary,
        ),
      ),
      title: Text(
        title,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: isDestructive ? colors.error : colors.onSurface,
        ),
      ),
      trailing:
          Icon(Icons.arrow_forward_ios, size: 14, color: colors.secondary),
      onTap: onTap,
    );
  }
}
