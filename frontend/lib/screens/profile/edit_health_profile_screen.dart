// lib/screens/profile/edit_health_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../config/app_translations.dart';
import '../../features/profile/domain/entities/onboarding_activity_choice.dart';
import '../../features/profile/domain/entities/profile_entity.dart';
import '../../providers/profile_provider.dart';
import '../../utils/auth_helper.dart';
import '../login/login_screen.dart';
import '../../services/unit_converter.dart';
import '../../widgets/saman_feedback_snackbar.dart';

/// Screen 07 — Edit Profile under Dark Calm Athleticism.
///
/// Features:
/// 1. Dedicated edit sub-screen with circular back button and context header.
/// 2. Prefilled from fresh backend-confirmed snapshot without mutating global state.
/// 3. Six distinct biometric fields:
///    - Goal (interactive photographic bottom sheet with Apply)
///    - Age (direct numeric entry, years suffix)
///    - Gender (Male/Female cards with radio dots; preserves Gender.other)
///    - Height (exact decimal entry, cm suffix)
///    - Weight (exact decimal entry, kg suffix)
///    - Activity level (5 canonical tiers bottom sheet with Apply)
/// 4. Discard confirmation dialog ("Keep editing" / "Discard changes") on Back when dirty.
/// 5. Docked 54px charcoal Save changes button: disabled when unchanged or invalid.
/// 6. Verified Save and Readback: commits snapshot and pops only after server confirmation.
/// 7. Idempotent error handling: 409 conflict, timeout unknown ("Check again" GET-only),
///    and identity mismatch lock.
class EditHealthProfileScreen extends ConsumerStatefulWidget {
  const EditHealthProfileScreen({super.key});

  @override
  ConsumerState<EditHealthProfileScreen> createState() =>
      _EditHealthProfileScreenState();
}

class _EditHealthProfileScreenState
    extends ConsumerState<EditHealthProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _ageController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;

  // Initial confirmed values (to determine dirty state)
  int? _initialAge;
  double? _initialHeight;
  double? _initialWeight;
  Gender? _initialGender;
  Goal? _initialGoal;
  OnboardingActivityChoice? _initialActivityChoice;
  String _initialAgeText = '';
  String _initialHeightText = '';
  String _initialWeightText = '';

  // Current draft values
  Gender? _selectedGender;
  Goal? _selectedGoal;
  OnboardingActivityChoice? _selectedActivityChoice;

  bool _isSaving = false;
  bool _isPrefilled = false;
  bool _hasUserInteracted = false;

  String? _ageError;
  String? _heightError;
  String? _weightError;

  @override
  void initState() {
    super.initState();
    _ageController = TextEditingController();
    _heightController = TextEditingController();
    _weightController = TextEditingController();

    _ageController.addListener(_onFieldChanged);
    _heightController.addListener(_onFieldChanged);
    _weightController.addListener(_onFieldChanged);

    final profile = ref.read(profileProvider).profile;
    if (_hasBiometrics(profile)) {
      _applyInitialData(profile);
      _isPrefilled = true;
    }
  }

  @override
  void dispose() {
    _ageController.removeListener(_onFieldChanged);
    _heightController.removeListener(_onFieldChanged);
    _weightController.removeListener(_onFieldChanged);

    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (_isPrefilled) {
      _hasUserInteracted = true;
    }
    _validateInputs();
    if (mounted) setState(() {});
  }

  bool _hasBiometrics(ProfileEntity p) {
    return p.age != null ||
        p.height != null ||
        p.weight != null ||
        p.hasGender ||
        p.hasActivityLevel ||
        p.hasGoal ||
        p.rawActivityCanonical != null;
  }

  String _formatDecimal(double? val) {
    if (val == null) return '';
    if (val % 1 == 0) {
      return val.toInt().toString();
    }
    return val.toString();
  }

  void _applyInitialData(ProfileEntity profile) {
    final unitSystem = ref.read(unitProvider);
    _initialAge = profile.age;
    _initialHeight = profile.height;
    _initialWeight = profile.weight;
    _initialGender = profile.rawGender;
    _initialGoal = profile.rawGoal;
    _initialActivityChoice =
        OnboardingActivityChoice.fromApi(profile.rawActivityCanonical) ??
            OnboardingActivityChoice.fromLegacy(profile.rawActivityLevel);

    _initialAgeText = _initialAge?.toString() ?? '';
    if (unitSystem == UnitSystem.imperial) {
      _initialHeightText = _initialHeight != null
          ? UnitConverter.formatDecimal(
              (UnitConverter.cmToInches(_initialHeight!) * 10).round() / 10)
          : '';
      _initialWeightText = _initialWeight != null
          ? UnitConverter.formatDecimal(
              (UnitConverter.kgToLb(_initialWeight!) * 10).round() / 10)
          : '';
    } else {
      _initialHeightText = _formatDecimal(_initialHeight);
      _initialWeightText = _formatDecimal(_initialWeight);
    }

    if (_initialAge != null) {
      _ageController.text = _initialAgeText;
    }
    if (_initialHeight != null) {
      _heightController.text = _initialHeightText;
    }
    if (_initialWeight != null) {
      _weightController.text = _initialWeightText;
    }

    _selectedGender = _initialGender;
    _selectedGoal = _initialGoal;
    _selectedActivityChoice = _initialActivityChoice;
  }

  void _validateInputs() {
    // Age validation
    final ageStr = _ageController.text.trim();
    if (ageStr.isEmpty) {
      _ageError = 'Vui lòng nhập tuổi';
    } else {
      final age = int.tryParse(ageStr);
      if (age == null) {
        _ageError = 'Tuổi phải là số nguyên';
      } else if (age < 13 || age > 120) {
        _ageError = 'Tuổi phải từ 13 đến 120';
      } else {
        _ageError = null;
      }
    }

    // Height validation
    final heightStr = _heightController.text.trim().replaceAll(',', '.');
    if (heightStr.isEmpty) {
      _heightError = 'Vui lòng nhập chiều cao';
    } else if (heightStr.endsWith('.')) {
      _heightError = 'Chiều cao phải là số hợp lệ';
    } else {
      final height = double.tryParse(heightStr);
      if (height == null) {
        _heightError = 'Chiều cao phải là số hợp lệ';
      } else if (height <= 0 || !height.isFinite) {
        _heightError = 'Chiều cao phải lớn hơn 0';
      } else {
        _heightError = null;
      }
    }

    // Weight validation
    final weightStr = _weightController.text.trim().replaceAll(',', '.');
    if (weightStr.isEmpty) {
      _weightError = 'Vui lòng nhập cân nặng';
    } else if (weightStr.endsWith('.')) {
      _weightError = 'Cân nặng phải là số hợp lệ';
    } else {
      final weight = double.tryParse(weightStr);
      if (weight == null) {
        _weightError = 'Cân nặng phải là số hợp lệ';
      } else if (weight <= 0 || !weight.isFinite) {
        _weightError = 'Cân nặng phải lớn hơn 0';
      } else {
        _weightError = null;
      }
    }
  }

  int? get _parsedAge => int.tryParse(_ageController.text.trim());
  double? get _parsedHeight => double.tryParse(
      _heightController.text.trim().replaceAll(',', '.'));
  double? get _parsedWeight => double.tryParse(
      _weightController.text.trim().replaceAll(',', '.'));

  bool get _isValid {
    return _ageError == null &&
        _heightError == null &&
        _weightError == null &&
        _parsedAge != null &&
        _parsedHeight != null &&
        _parsedWeight != null;
  }

  bool get _isHeightDirty {
    final raw = _heightController.text.trim().replaceAll(',', '.');
    if (_initialHeight == null) {
      return raw.isNotEmpty;
    }
    if (raw.endsWith('.') || raw.isEmpty) {
      return raw != _initialHeightText;
    }
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      return raw != _initialHeightText;
    }
    if (ref.read(unitProvider) == UnitSystem.imperial) {
      return raw != _initialHeightText;
    }
    return parsed != _initialHeight;
  }

  bool get _isWeightDirty {
    final raw = _weightController.text.trim().replaceAll(',', '.');
    if (_initialWeight == null) {
      return raw.isNotEmpty;
    }
    if (raw.endsWith('.') || raw.isEmpty) {
      return raw != _initialWeightText;
    }
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      return raw != _initialWeightText;
    }
    if (ref.read(unitProvider) == UnitSystem.imperial) {
      return raw != _initialWeightText;
    }
    return parsed != _initialWeight;
  }

  bool get _isAgeDirty {
    final raw = _ageController.text.trim();
    if (_initialAge == null) {
      return raw.isNotEmpty;
    }
    if (raw.isEmpty) {
      return raw != _initialAgeText;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      return raw != _initialAgeText;
    }
    return parsed != _initialAge;
  }

  bool get _isGenderDirty => _selectedGender != _initialGender;
  bool get _isGoalDirty => _selectedGoal != _initialGoal;
  bool get _isActivityDirty => _selectedActivityChoice != _initialActivityChoice;

  bool get _isDirty {
    return _isAgeDirty ||
        _isHeightDirty ||
        _isWeightDirty ||
        _isGenderDirty ||
        _isGoalDirty ||
        _isActivityDirty;
  }

  Future<void> _handleBack() async {
    final state = ref.read(profileProvider);
    if (_isSaving || state.status == ProfileStatus.saving || state.status == ProfileStatus.readbackPending) {
      return; // Block pop during mutation
    }

    if (state.status == ProfileStatus.identityMismatch) {
      _showIdentityMismatchDialog();
      return;
    }

    if (_isDirty) {
      final discard = await _showDiscardDialog();
      if (discard == true && mounted) {
        Navigator.pop(context, false);
      }
    } else {
      Navigator.pop(context, false);
    }
  }

  Future<bool?> _showDiscardDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final palette = ctx.samanColors;
        final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
        final keepBg =
            palette.isDark ? const Color(0xFF212328) : palette.surfaceElevated;
        return AlertDialog(
          backgroundColor: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: palette.border, width: 1),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: keepBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: palette.amber,
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Discard changes?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your changes haven’t been saved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const Key('discard_dialog_keep_editing'),
                  onPressed: () => Navigator.pop(ctx, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: keepBg,
                    foregroundColor: textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: palette.border),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Keep editing',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  key: const Key('discard_dialog_discard'),
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    backgroundColor: palette.surface,
                    foregroundColor: palette.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: palette.border),
                    ),
                  ),
                  child: const Text(
                    'Discard changes',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showIdentityMismatchDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final palette = ctx.samanColors;
        final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
        final dangerColor =
            palette.isDark ? const Color(0xFFEF4444) : palette.danger;
        return AlertDialog(
          backgroundColor: palette.surface,
          title: Text('Xác thực thất bại', style: TextStyle(color: textPrimary)),
          content: Text(
            'Chủ tài khoản không khớp với phiên làm việc hiện tại. Vui lòng đăng nhập lại.',
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await AuthHelper.logout(ref);
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: dangerColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );
  }

  void _openGoalSheet() async {
    final currentChoice = _selectedGoal;
    Goal? tempSelection = currentChoice;

    final result = await showModalBottomSheet<Goal>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final palette = ctx.samanColors;
            final sheetBg =
                palette.isDark ? const Color(0xFF121316) : palette.surface;
            final handleColor =
                palette.isDark ? const Color(0xFF52525B) : palette.border;
            final textPrimary =
                palette.isDark ? Colors.white : palette.textPrimary;
            final applyBg =
                palette.isDark ? const Color(0xFF212328) : palette.accent;
            final applyFg = palette.isDark ? Colors.white : palette.onAccent;
            return Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(top: BorderSide(color: palette.border, width: 1)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: handleColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          ctx.tr('choose_your_goal'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: palette.textSecondary, size: 18),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildGoalOptionCard(
                      ctx,
                      goal: Goal.lose_weight,
                      title: ctx.tr('lose_weight'),
                      subtitle: ctx.tr('goal_lose_weight_desc'),
                      asset: 'assets/profile/goal_lose_weight.jpg',
                      keyName: 'enum_lose_weight',
                      isSelected: tempSelection == Goal.lose_weight,
                      onTap: () => setSheetState(() => tempSelection = Goal.lose_weight),
                    ),
                    const SizedBox(height: 10),
                    _buildGoalOptionCard(
                      ctx,
                      goal: Goal.maintain_weight,
                      title: ctx.tr('maintain_weight'),
                      subtitle: ctx.tr('goal_maintain_weight_desc'),
                      asset: 'assets/profile/goal_maintain_weight.jpg',
                      keyName: 'enum_maintain_weight',
                      isSelected: tempSelection == Goal.maintain_weight,
                      onTap: () => setSheetState(() => tempSelection = Goal.maintain_weight),
                    ),
                    const SizedBox(height: 10),
                    _buildGoalOptionCard(
                      ctx,
                      goal: Goal.gain_muscle,
                      title: ctx.tr('gain_muscle'),
                      subtitle: ctx.tr('goal_build_muscle_desc'),
                      asset: 'assets/profile/goal_build_muscle.jpg',
                      keyName: 'enum_gain_muscle',
                      isSelected: tempSelection == Goal.gain_muscle,
                      onTap: () => setSheetState(() => tempSelection = Goal.gain_muscle),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        key: const Key('goal_sheet_apply_button'),
                        onPressed: () => Navigator.pop(ctx, tempSelection),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: applyBg,
                          foregroundColor: applyFg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: palette.isDark
                                ? BorderSide(color: palette.border)
                                : BorderSide.none,
                          ),
                          elevation: 0,
                        ),
                        child: Text(ctx.tr('apply_btn'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && result != _selectedGoal) {
      setState(() {
        _hasUserInteracted = true;
        _selectedGoal = result;
      });
    }
  }

  Widget _buildGoalOptionCard(
    BuildContext context, {
    required Goal goal,
    required String title,
    required String subtitle,
    required String asset,
    required String keyName,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final palette = context.samanColors;
    final selectedBg =
        palette.isDark ? const Color(0xFF1C1D22) : palette.surfaceElevated;
    final cardBg = isSelected ? selectedBg : palette.surface;
    final selectedBorder =
        palette.isDark ? const Color(0xFFE5E7EB) : palette.textPrimary;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    final selectedSubtitle =
        palette.isDark ? const Color(0xFFD1D5DB) : palette.textPrimary;
    final radioActive = palette.isDark ? Colors.white : palette.textPrimary;

    return InkWell(
      key: Key(keyName),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? selectedBorder : palette.border,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 120,
              child: IgnorePointer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      opacity: AlwaysStoppedAnimation(palette.isDark ? 0.25 : 0.16),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            cardBg,
                            cardBg.withOpacity(0.6),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? selectedSubtitle
                                : palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? radioActive : palette.textMuted,
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: radioActive,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openActivitySheet() async {
    final currentChoice = _selectedActivityChoice;
    OnboardingActivityChoice? tempSelection = currentChoice;

    final result = await showModalBottomSheet<OnboardingActivityChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final palette = ctx.samanColors;
            final sheetBg =
                palette.isDark ? const Color(0xFF121316) : palette.surface;
            final handleColor =
                palette.isDark ? const Color(0xFF52525B) : palette.border;
            final textPrimary =
                palette.isDark ? Colors.white : palette.textPrimary;
            final selectedBg =
                palette.isDark ? const Color(0xFF1C1D22) : palette.surfaceElevated;
            final selectedBorder =
                palette.isDark ? const Color(0xFFE5E7EB) : palette.textPrimary;
            final selectedSubtitle =
                palette.isDark ? const Color(0xFFD1D5DB) : palette.textPrimary;
            final radioActive =
                palette.isDark ? Colors.white : palette.textPrimary;
            final applyBg =
                palette.isDark ? const Color(0xFF212328) : palette.accent;
            final applyFg = palette.isDark ? Colors.white : palette.onAccent;

            return Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(top: BorderSide(color: palette.border, width: 1)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: handleColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          ctx.tr('activity_level_dialog_title'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: palette.textSecondary, size: 18),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...OnboardingActivityChoice.values.map((choice) {
                      final isSelected = tempSelection == choice;
                      final keyPrefix = choice == OnboardingActivityChoice.sedentary
                          ? 'activity_option_sedentary'
                          : choice == OnboardingActivityChoice.light
                              ? 'activity_option_light'
                              : choice == OnboardingActivityChoice.moderate
                                  ? 'activity_option_moderate'
                                  : choice == OnboardingActivityChoice.active
                                      ? 'activity_option_active'
                                      : 'activity_option_very_active';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          key: Key(keyPrefix),
                          onTap: () => setSheetState(() => tempSelection = choice),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? selectedBg : palette.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? selectedBorder : palette.border,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        choice.title,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        choice.subtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isSelected
                                              ? selectedSubtitle
                                              : palette.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? radioActive : palette.textMuted,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Center(
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: radioActive,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        key: const Key('activity_sheet_apply_button'),
                        onPressed: () => Navigator.pop(ctx, tempSelection),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: applyBg,
                          foregroundColor: applyFg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: palette.isDark
                                ? BorderSide(color: palette.border)
                                : BorderSide.none,
                          ),
                          elevation: 0,
                        ),
                        child: Text(ctx.tr('apply_btn'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && result != _selectedActivityChoice) {
      setState(() {
        _hasUserInteracted = true;
        _selectedActivityChoice = result;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    _validateInputs();
    if (!_isValid) return;

    setState(() => _isSaving = true);

    try {
      final gender = _selectedGender ?? _initialGender ?? Gender.male;
      final goal = _selectedGoal ?? _initialGoal ?? Goal.maintain_weight;
      final activityChoice = _selectedActivityChoice ??
          _initialActivityChoice ??
          OnboardingActivityChoice.moderate;

      final unitSystem = ref.read(unitProvider);
      final double finalHeight;
      if (_heightController.text.trim() == _initialHeightText && _initialHeight != null) {
        finalHeight = _initialHeight!;
      } else if (unitSystem == UnitSystem.imperial) {
        finalHeight = UnitConverter.inchesToCm(_parsedHeight!);
      } else {
        finalHeight = _parsedHeight!;
      }

      final double finalWeight;
      if (_weightController.text.trim() == _initialWeightText && _initialWeight != null) {
        finalWeight = _initialWeight!;
      } else if (unitSystem == UnitSystem.imperial) {
        finalWeight = UnitConverter.lbToKg(_parsedWeight!);
      } else {
        finalWeight = _parsedWeight!;
      }

      final success = await ref
          .read(profileProvider.notifier)
          .saveAndVerifyEditProfile(
            age: _parsedAge!,
            height: finalHeight,
            weight: finalWeight,
            gender: gender,
            goal: goal,
            activityChoice: activityChoice,
          );

      if (!mounted) return;

      if (success) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Profile updated',
          type: FeedbackType.success,
        );
        Navigator.pop(context, true);
      } else {
        setState(() => _isSaving = false);
        final errorMsg = ref.read(profileProvider).errorMessage;
        if (errorMsg != null && errorMsg.isNotEmpty) {
          SamanFeedbackSnackBar.show(
            context,
            message: errorMsg,
            type: FeedbackType.error,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      SamanFeedbackSnackBar.show(
        context,
        message: 'Lỗi cập nhật: ${e.toString()}',
        type: FeedbackType.error,
      );
    }
  }

  Future<void> _checkAgain() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final gender = _selectedGender ?? _initialGender ?? Gender.male;
      final goal = _selectedGoal ?? _initialGoal ?? Goal.maintain_weight;
      final activityChoice = _selectedActivityChoice ??
          _initialActivityChoice ??
          OnboardingActivityChoice.moderate;

      final success = await ref
          .read(profileProvider.notifier)
          .reconcileEditProfile(
            age: _parsedAge!,
            height: _parsedHeight!,
            weight: _parsedWeight!,
            gender: gender,
            goal: goal,
            activityChoice: activityChoice,
          );

      if (!mounted) return;
      if (success) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Profile updated',
          type: FeedbackType.success,
        );
        Navigator.pop(context, true);
      } else {
        setState(() => _isSaving = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for late-arriving confirmed profile
    ref.listen<ProfileState>(profileProvider, (previous, next) {
      final p = next.profile;
      if (!_isPrefilled && !_hasUserInteracted && _hasBiometrics(p)) {
        setState(() {
          _applyInitialData(p);
          _isPrefilled = true;
        });
      }
    });

    final profileState = ref.watch(profileProvider);
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final isSavingInFlight = _isSaving ||
        profileState.status == ProfileStatus.saving;
    final isSaveTimeout = profileState.status == ProfileStatus.saveTimeoutUnknown;
    final isReadbackPending = profileState.status == ProfileStatus.readbackPending;
    final isConflict = profileState.status == ProfileStatus.saveConflict;
    final isMismatch = profileState.status == ProfileStatus.identityMismatch;

    final isSaveEnabled =
        _isDirty && _isValid && !isSavingInFlight && !isMismatch;
    final palette = context.samanColors;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    final iconBoxBg =
        palette.isDark ? const Color(0xFF212328) : palette.surfaceElevated;
    final dangerColor =
        palette.isDark ? const Color(0xFFEF4444) : palette.danger;
    final saveDisabledBg =
        palette.isDark ? const Color(0xFF1E2026) : const Color(0xFFE2E8F0);
    final saveDisabledFg =
        palette.isDark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);
    final saveDisabledBorder =
        palette.isDark ? const Color(0xFF383A42) : const Color(0xFFCBD5E1);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: palette.canvas,
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
                      opacity: AlwaysStoppedAnimation(palette.isDark ? 0.25 : 0.14),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            palette.canvas,
                            palette.canvas.withOpacity(0.8),
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
                            palette.canvas,
                            palette.canvas.withOpacity(0.7),
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
              child: Column(
                children: [
                  // Top Context Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            InkWell(
                              key: const Key('edit_profile_back_button'),
                              onTap: _handleBack,
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: palette.surface,
                                  border: Border.all(
                                    color: palette.border,
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.arrow_back,
                                  size: 18,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Edit profile',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Update your details when things change.',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status / Error Banners
                  if (isConflict) ...[
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.amber),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.sync_problem, color: palette.amber, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Dữ liệu hồ sơ đã được cập nhật từ thiết bị khác. Vui lòng kiểm tra lại.',
                              style: TextStyle(fontSize: 12, color: textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (isSaveTimeout || isReadbackPending) ...[
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.amber),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              color: palette.amber, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your changes were saved. We couldn’t confirm them yet.',
                              style: TextStyle(fontSize: 12, color: textPrimary),
                            ),
                          ),
                          TextButton(
                            key: const Key('edit_profile_check_again_button'),
                            onPressed: _checkAgain,
                            style: TextButton.styleFrom(
                              backgroundColor: iconBoxBg,
                              foregroundColor: textPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            child: Text(context.tr('check_again'), style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ] else if (isMismatch) ...[
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: dangerColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: dangerColor, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Xác thực thất bại: Chủ tài khoản không khớp.',
                              style: TextStyle(fontSize: 12, color: textPrimary),
                            ),
                          ),
                          TextButton(
                            onPressed: _showIdentityMismatchDialog,
                            style: TextButton.styleFrom(
                              backgroundColor: iconBoxBg,
                              foregroundColor: dangerColor,
                            ),
                            child: const Text('Log out', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Scrollable Form
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        10,
                        20,
                        isKeyboardOpen ? 40 : 120,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. YOUR GOAL
                            Text(
                              context.tr('your_goal'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: palette.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              key: const Key('edit_profile_goal_tile'),
                              onTap: _openGoalSheet,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: palette.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: palette.border,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: iconBoxBg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: palette.border,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.fitness_center,
                                        size: 18,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _selectedGoal != null
                                                ? (_selectedGoal == Goal.lose_weight
                                                    ? context.tr('lose_weight')
                                                    : _selectedGoal ==
                                                            Goal.maintain_weight
                                                        ? context.tr('maintain_weight')
                                                        : context.tr('gain_muscle'))
                                                : context.tr('choose_your_goal'),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _selectedGoal != null
                                                ? (_selectedGoal == Goal.lose_weight
                                                    ? context.tr('goal_lose_weight_desc')
                                                    : _selectedGoal ==
                                                            Goal.maintain_weight
                                                        ? context.tr('goal_maintain_weight_desc')
                                                        : context.tr('goal_build_muscle_desc'))
                                                : '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: palette.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: palette.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 2. ABOUT YOU
                            Text(
                              context.tr('section_about_you'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: palette.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Age Input Card
                            _buildNumericCard(
                              label: context.tr('age_label'),
                              suffix: context.tr('unit_years'),
                              controller: _ageController,
                              fieldKey: const Key('edit_profile_age_input'),
                              keyboardType: TextInputType.number,
                              errorText: _ageError,
                            ),
                            const SizedBox(height: 12),

                            // Gender Selection Matrix
                            Text(
                              context.tr('gender'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: palette.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildGenderCard(
                                    gender: Gender.male,
                                    label: context.tr('male'),
                                    icon: Icons.male,
                                    keyName: 'enum_male',
                                    isSelected: _selectedGender == Gender.male,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildGenderCard(
                                    gender: Gender.female,
                                    label: context.tr('female'),
                                    icon: Icons.female,
                                    keyName: 'enum_female',
                                    isSelected: _selectedGender == Gender.female,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // 3. BODY MEASUREMENTS
                            Text(
                              context.tr('section_body_measurements'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: palette.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Height Input Card
                            _buildNumericCard(
                              label: context.tr('height_label'),
                              suffix: ref.watch(unitProvider) == UnitSystem.imperial ? 'in' : 'cm',
                              controller: _heightController,
                              fieldKey: const Key('edit_profile_height_input'),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              errorText: _heightError,
                            ),
                            const SizedBox(height: 12),

                            // Weight Input Card
                            _buildNumericCard(
                              label: context.tr('weight_label'),
                              suffix: ref.watch(unitProvider) == UnitSystem.imperial ? 'lb' : 'kg',
                              controller: _weightController,
                              fieldKey: const Key('edit_profile_weight_input'),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              errorText: _weightError,
                            ),
                            const SizedBox(height: 24),

                            // 4. ACTIVITY LEVEL
                            Text(
                              context.tr('activity_level_heading'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: palette.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),

                            InkWell(
                              key: const Key('edit_profile_activity_tile'),
                              onTap: _openActivitySheet,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: palette.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: palette.border,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: iconBoxBg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: palette.border,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.directions_walk,
                                        size: 18,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _selectedActivityChoice?.title ??
                                                context.tr('select_activity_level'),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _selectedActivityChoice?.subtitle ??
                                                '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: palette.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: palette.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Fixed Bottom Action Dock (hidden when keyboard is open per Frame G)
            if (!isKeyboardOpen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        palette.canvas,
                        palette.canvas.withOpacity(0.95),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        key: const Key('edit_profile_save_button'),
                        onPressed: isSavingInFlight || isMismatch
                            ? null
                            : () {
                                _hasUserInteracted = true;
                                _validateInputs();
                                if (!_isDirty || !_isValid) {
                                  setState(() {});
                                  return;
                                }
                                _saveChanges();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isSaveEnabled ? palette.accent : saveDisabledBg,
                          foregroundColor:
                              isSaveEnabled ? palette.onAccent : saveDisabledFg,
                          disabledBackgroundColor:
                              isSaveEnabled ? palette.accent : saveDisabledBg,
                          disabledForegroundColor:
                              isSaveEnabled ? palette.onAccent : saveDisabledFg,
                          elevation: isSaveEnabled ? 4 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: isSaveEnabled
                                ? BorderSide.none
                                : BorderSide(
                                    color: saveDisabledBorder,
                                    width: 1,
                                  ),
                          ),
                        ),
                        child: isSavingInFlight
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: palette.onAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Saving…',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                context.tr('save_changes'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumericCard({
    required String label,
    required String suffix,
    required TextEditingController controller,
    required Key fieldKey,
    required TextInputType keyboardType,
    String? errorText,
  }) {
    final palette = context.samanColors;
    final dangerColor =
        palette.isDark ? const Color(0xFFEF4444) : palette.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: errorText != null ? dangerColor : palette.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: TextFormField(
                  key: fieldKey,
                  controller: controller,
                  keyboardType: keyboardType,
                  cursorColor: palette.textPrimary,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                  onTap: () => _hasUserInteracted = true,
                  onChanged: (_) => _hasUserInteracted = true,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                suffix,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 4),
            Text(
              errorText,
              style: TextStyle(
                fontSize: 11,
                color: dangerColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGenderCard({
    required Gender gender,
    required String label,
    required IconData icon,
    required String keyName,
    required bool isSelected,
  }) {
    final palette = context.samanColors;
    final selectedBg =
        palette.isDark ? const Color(0xFF1C1D22) : palette.surfaceElevated;
    final selectedBorder =
        palette.isDark ? const Color(0xFFE5E7EB) : palette.textPrimary;
    final activeColor = palette.isDark ? Colors.white : palette.textPrimary;
    final unselectedLabel =
        palette.isDark ? const Color(0xFFD1D5DB) : palette.textSecondary;

    return InkWell(
      key: Key(keyName),
      onTap: () {
        setState(() {
          _hasUserInteracted = true;
          _selectedGender = gender;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? selectedBorder : palette.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? activeColor : palette.textSecondary,
                ),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? activeColor : palette.textMuted,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: activeColor,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected ? activeColor : unselectedLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
