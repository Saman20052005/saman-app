import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../config/app_translations.dart';
import '../../features/profile/domain/entities/profile_entity.dart';
import '../../providers/profile_provider.dart';

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

  Gender? _selectedGender;
  ActivityLevel? _selectedActivity;
  Goal? _selectedGoal;

  bool _isSaving = false;
  bool _isPrefilled = false;
  bool _isDirty = false;

  bool _hasProfileData(ProfileEntity p) {
    return p.age != null ||
        p.height != null ||
        p.weight != null ||
        p.hasGender ||
        p.hasActivityLevel ||
        p.hasGoal;
  }

  void _applyProfileData(ProfileEntity profile) {
    if (profile.age != null) {
      _ageController.text = profile.age.toString();
    }
    if (profile.height != null) {
      _heightController.text = (profile.height! % 1 == 0
          ? profile.height!.toInt().toString()
          : profile.height!.toString());
    }
    if (profile.weight != null) {
      _weightController.text = (profile.weight! % 1 == 0
          ? profile.weight!.toInt().toString()
          : profile.weight!.toString());
    }
    if (profile.hasGender) {
      _selectedGender = profile.rawGender;
    }
    if (profile.hasActivityLevel) {
      _selectedActivity = profile.rawActivityLevel;
    }
    if (profile.hasGoal) {
      _selectedGoal = profile.rawGoal;
    }
  }

  @override
  void initState() {
    super.initState();
    _ageController = TextEditingController();
    _heightController = TextEditingController();
    _weightController = TextEditingController();

    final profile = ref.read(profileProvider).profile;
    if (_hasProfileData(profile)) {
      _applyProfileData(profile);
      _isPrefilled = true;
    }
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String _tr(String key) {
    final locale = ref.read(languageProvider);
    return AppTranslations.text(key, locale);
  }

  String? _validateAge(String? val) {
    final text = val?.trim() ?? '';
    if (text.isEmpty) {
      return 'Vui lòng nhập tuổi';
    }
    final age = int.tryParse(text);
    if (age == null) {
      return 'Tuổi phải là số nguyên';
    }
    if (age < 13 || age > 120) {
      return 'Tuổi phải từ 13 đến 120';
    }
    return null;
  }

  String? _validateHeight(String? val) {
    final text = val?.trim() ?? '';
    if (text.isEmpty) {
      return 'Vui lòng nhập chiều cao';
    }
    final height = double.tryParse(text);
    if (height == null) {
      return 'Chiều cao phải là số hợp lệ';
    }
    if (height <= 0) {
      return 'Chiều cao phải lớn hơn 0';
    }
    return null;
  }

  String? _validateWeight(String? val) {
    final text = val?.trim() ?? '';
    if (text.isEmpty) {
      return 'Vui lòng nhập cân nặng';
    }
    final weight = double.tryParse(text);
    if (weight == null) {
      return 'Cân nặng phải là số hợp lệ';
    }
    if (weight <= 0) {
      return 'Cân nặng phải lớn hơn 0';
    }
    return null;
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final age = int.parse(_ageController.text.trim());
    final height = double.parse(_heightController.text.trim());
    final weight = double.parse(_weightController.text.trim());

    final newProfile = ProfileEntity(
      age: age,
      height: height,
      weight: weight,
      gender: _selectedGender,
      activityLevel: _selectedActivity,
      goal: _selectedGoal,
    );

    try {
      await ref.read(profileProvider.notifier).updateProfile(newProfile);
      if (!mounted) return;

      if (ref.read(profileProvider).isUnauthorized) {
        setState(() => _isSaving = false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('update_success')),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);

      if (ref.read(profileProvider).isUnauthorized) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi cập nhật: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ProfileState>(profileProvider, (previous, next) {
      final p = next.profile;
      if (!_isPrefilled && !_isDirty && _hasProfileData(p)) {
        setState(() {
          _applyProfileData(p);
          _isPrefilled = true;
        });
      }
    });

    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _tr('edit_profile_title'),
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EditProfileSectionHeader(
                  title: _tr('body_stats'),
                  icon: Icons.accessibility_new,
                ),
                const SizedBox(height: AppSpacing.lg),
                EditProfileNumericField(
                  fieldKey: const Key('edit_profile_age_input'),
                  label: _tr('age'),
                  suffix: '',
                  controller: _ageController,
                  validator: _validateAge,
                  keyboardType: TextInputType.number,
                  hintText: '13 - 120',
                  onChanged: (_) => _isDirty = true,
                ),
                const SizedBox(height: AppSpacing.md),
                EditProfileNumericField(
                  fieldKey: const Key('edit_profile_height_input'),
                  label: _tr('height'),
                  suffix: 'cm',
                  controller: _heightController,
                  validator: _validateHeight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  hintText: 'VD: 175',
                  onChanged: (_) => _isDirty = true,
                ),
                const SizedBox(height: AppSpacing.md),
                EditProfileNumericField(
                  fieldKey: const Key('edit_profile_weight_input'),
                  label: _tr('weight'),
                  suffix: 'kg',
                  controller: _weightController,
                  validator: _validateWeight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  hintText: 'VD: 70',
                  onChanged: (_) => _isDirty = true,
                ),
                const SizedBox(height: AppSpacing.xxl),
                EditProfileSectionHeader(
                  title: _tr('goal_lifestyle'),
                  icon: Icons.flag,
                ),
                const SizedBox(height: AppSpacing.lg),
                EditProfileEnumSelection<Goal>(
                  title: _tr('main_goal'),
                  options: Goal.values,
                  selectedValue: _selectedGoal,
                  onSelected: (val) {
                    _isDirty = true;
                    setState(() => _selectedGoal = val);
                  },
                  labelBuilder: (goal) => _tr(goal.name),
                ),
                const SizedBox(height: AppSpacing.md),
                EditProfileEnumSelection<ActivityLevel>(
                  title: _tr('activity_level'),
                  options: ActivityLevel.values,
                  selectedValue: _selectedActivity,
                  onSelected: (val) {
                    _isDirty = true;
                    setState(() => _selectedActivity = val);
                  },
                  labelBuilder: (lvl) => _tr(lvl.name),
                ),
                const SizedBox(height: AppSpacing.md),
                EditProfileEnumSelection<Gender>(
                  title: _tr('gender'),
                  options: Gender.values,
                  selectedValue: _selectedGender,
                  onSelected: (val) {
                    _isDirty = true;
                    setState(() => _selectedGender = val);
                  },
                  labelBuilder: (gender) => _tr(gender.name),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                EditProfileSaveButton(
                  isSaving: _isSaving,
                  label: _tr('save_changes'),
                  onPressed: _saveProfile,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditProfileSectionHeader extends StatelessWidget {
  const EditProfileSectionHeader({
    required this.title,
    required this.icon,
    super.key,
  });

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

class EditProfileNumericField extends StatelessWidget {
  const EditProfileNumericField({
    required this.label,
    required this.suffix,
    required this.controller,
    required this.validator,
    required this.keyboardType,
    required this.hintText,
    this.fieldKey,
    this.onChanged,
    super.key,
  });

  final String label;
  final String suffix;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final TextInputType keyboardType;
  final String hintText;
  final Key? fieldKey;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              if (suffix.isNotEmpty)
                Text(
                  suffix,
                  style: textTheme.bodySmall?.copyWith(color: colors.secondary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            key: fieldKey,
            controller: controller,
            keyboardType: keyboardType,
            validator: validator,
            onChanged: onChanged,
            style: textTheme.bodyLarge?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: textTheme.bodyMedium?.copyWith(
                color: colors.secondary.withOpacity(0.6),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditProfileEnumSelection<T extends Enum> extends StatelessWidget {
  const EditProfileEnumSelection({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    required this.labelBuilder,
    super.key,
  });

  final String title;
  final List<T> options;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final String Function(T) labelBuilder;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((option) {
                final isSelected = selectedValue == option;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: InkWell(
                    key: Key('enum_${option.name}'),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => onSelected(option),
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
                        labelBuilder(option),
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
}

class EditProfileSaveButton extends StatelessWidget {
  const EditProfileSaveButton({
    required this.isSaving,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final bool isSaving;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        key: const Key('edit_profile_save_button'),
        onPressed: isSaving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: isSaving
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colors.onPrimary,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
