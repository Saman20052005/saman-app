import 'package:flutter/material.dart';

import '../../../../config/app_translations.dart';
import '../../../../models/nutrition_model.dart';
import '../../../../theme/nutrition_home_theme.dart';

export 'nutrition_quick_log_and_usuals.dart';

class NutritionFoodHero extends StatelessWidget {
  const NutritionFoodHero(
      {required this.onReport,
      required this.membershipBadge,
      this.asset = foodAsset,
      super.key});
  static const foodAsset = 'assets/images/nutrition/food-hero.png';
  final VoidCallback onReport;
  final Widget membershipBadge;
  final String asset;
  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 190),
      child: Stack(children: [
        Positioned.fill(
            child: Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => ColoredBox(color: s.canvas),
        )),
        Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            s.heroShadow,
            s.canvas.withOpacity(0.8),
            Colors.transparent
          ], stops: const [
            0,
            0.42,
            1
          ]),
        ))),
        Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, s.canvas],
              stops: const [0.55, 1]),
        ))),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: membershipBadge)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  style: s.secondaryAction,
                  onPressed: onReport,
                  icon:
                      Icon(Icons.bar_chart_rounded, size: 16, color: s.accent),
                  label: const Text('Report')),
            ]),
            const SizedBox(height: 25),
            Text('Nutrition', style: s.title),
            const SizedBox(height: 6),
            Text('Fuel, log & track your day', style: s.caption),
          ]),
        ),
      ]),
    );
  }
}

class NutritionMembershipBadge extends StatelessWidget {
  const NutritionMembershipBadge(
      {required this.label, required this.onPressed, super.key});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
          foregroundColor: s.accent,
          backgroundColor: s.surface,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: s.pillRadius),
          side: BorderSide(color: s.border),
          textStyle: s.label),
      child: Text(label, textAlign: TextAlign.start),
    );
  }
}

class NutritionQuickActions extends StatelessWidget {
  const NutritionQuickActions(
      {required this.onLogMeal, required this.onScanFood, super.key});
  final VoidCallback onLogMeal, onScanFood;
  @override
  Widget build(BuildContext context) {
    final s = NutritionHomeStyle.of(context);
    return LayoutBuilder(builder: (context, box) {
      final log = FilledButton.icon(
          style: s.primaryAction,
          onPressed: onLogMeal,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Log meal'));
      final scan = OutlinedButton.icon(
          style: s.secondaryAction,
          onPressed: onScanFood,
          icon: const Icon(Icons.camera_alt_outlined, size: 20),
          label: const Text('Scan food'));
      return box.maxWidth < 340 &&
              MediaQuery.textScalerOf(context).scale(14) > 20
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [log, const SizedBox(height: 10), scan])
          : Row(children: [
              Expanded(child: log),
              const SizedBox(width: 12),
              Expanded(child: scan)
            ]);
    });
  }
}

class NutritionMealsHeading extends StatelessWidget {
  const NutritionMealsHeading({required this.onMealStory, super.key});
  final VoidCallback onMealStory;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).extension<NutritionHomeStyle>() ??
        const NutritionHomeStyle();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            context.tr('logged_meals_heading'),
            style: s.section.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: s.ink,
              letterSpacing: -0.3,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onMealStory,
          style: TextButton.styleFrom(
            foregroundColor: s.accent,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            minimumSize: const Size(48, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.auto_stories_outlined, size: 16),
          label: Text(
            context.tr('meal_story'),
            style: TextStyle(
              color: s.accent,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class NutritionEmptyMeals extends StatelessWidget {
  const NutritionEmptyMeals({
    this.selectedDate,
    this.asset = defaultAsset,
    super.key,
  });

  final DateTime? selectedDate;
  final String asset;
  static const defaultAsset =
      'assets/images/nutrition/logged_meals_empty_toast_egg.webp';

  bool _isToday(DateTime? date) {
    if (date == null) return true;
    final nowVn = DateTime.now().toUtc().add(const Duration(hours: 7));
    final dateVn = date.isUtc ? date.add(const Duration(hours: 7)) : date;
    if (dateVn.year == nowVn.year &&
        dateVn.month == nowVn.month &&
        dateVn.day == nowVn.day) {
      return true;
    }
    final localNow = DateTime.now();
    return date.year == localNow.year &&
        date.month == localNow.month &&
        date.day == localNow.day;
  }

  @override
  Widget build(BuildContext context) {
    return NutritionHomeTheme(
      child: Builder(
        builder: (context) {
          final s = Theme.of(context).extension<NutritionHomeStyle>() ??
              const NutritionHomeStyle();
          final isToday = _isToday(selectedDate);
          final cardRadius = BorderRadius.circular(22);

          return LayoutBuilder(
            builder: (context, constraints) {
              final textScaler = MediaQuery.textScalerOf(context);
              final isLargeText = textScaler.scale(14) > 20;
              final isNarrow = constraints.maxWidth < 340;
              final hideSupporting = isNarrow && isLargeText;

              return ClipRRect(
                borderRadius: cardRadius,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: cardRadius,
                    border: Border.all(color: s.border, width: 1),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 185),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            asset,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            excludeFromSemantics: true,
                            errorBuilder: (_, __, ___) =>
                                ColoredBox(color: s.surface),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: const [0.0, 0.40, 0.70, 1.0],
                                colors: [
                                  s.surface,
                                  s.surface.withOpacity(0.96),
                                  s.surface.withOpacity(0.60),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.75, 1.0],
                                colors: [
                                  s.surface.withOpacity(0.40),
                                  Colors.transparent,
                                  s.surface.withOpacity(0.40),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 18),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (isLargeText || isNarrow)
                                  ? double.infinity
                                  : constraints.maxWidth * 0.65,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0x3326282F),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0x44353842),
                                        width: 1),
                                  ),
                                  child: Text(
                                    context.tr('empty_meals_eyebrow'),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: Color(0xFF94979E),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  context.tr('empty_meals_title'),
                                  style: s.strong.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    height: 1.18,
                                    color: s.ink,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isToday
                                      ? context.tr('empty_meals_today')
                                      : context.tr('empty_meals_other_day'),
                                  style: s.body.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: const Color(0xFFD1D5DB),
                                    height: 1.3,
                                  ),
                                ),
                                if (!hideSupporting) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    context.tr('empty_meals_supporting'),
                                    style: s.caption.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: const Color(0xFF94979E),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Read-only details from the selected logged entry, never a planned meal.
class NutritionLoggedMealDetails extends StatelessWidget {
  const NutritionLoggedMealDetails({required this.entry, super.key});
  final NutritionLogEntry entry;
  @override
  Widget build(BuildContext context) => DefaultTextStyle(
      style: NutritionHomeStyle.of(context).body,
      child: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                      tooltip: 'Close meal details',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close,
                          color: NutritionHomeStyle.of(context).muted))),
              Text(entry.foodName,
                  style: NutritionHomeStyle.of(context).section),
              const SizedBox(height: 12),
              Text('${entry.totalCalories} kcal'),
              Text(
                  '${entry.protein.toInt()}g pro · ${entry.carbs.toInt()}g carb · ${entry.fat.toInt()}g fat'),
              for (final food in entry.foods)
                if (food['name'] != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(food['name'].toString())),
            ]),
      )));
}
