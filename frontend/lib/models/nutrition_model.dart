// [File: lib/models/nutrition_model.dart]

class MacroTargets {
  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  const MacroTargets({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  factory MacroTargets.fromJson(Map<String, dynamic> json) => MacroTargets(
        calories: (json['calories'] as num?)?.toInt() ?? 2000,
        protein: (json['protein'] as num?)?.toDouble() ?? 50,
        carbs: (json['carbs'] as num?)?.toDouble() ?? 250,
        fat: (json['fat'] as num?)?.toDouble() ?? 65,
      );

  /// Fallback khi chưa có data từ backend
  static const defaultTargets = MacroTargets(
    calories: 2000,
    protein: 50,
    carbs: 250,
    fat: 65,
  );
}

class NutritionLogEntry {
  final String logId;
  final String foodName;
  final String mealType;
  final int totalCalories;
  final double protein;
  final double carbs;
  final double fat;
  final List<Map<String, dynamic>> foods;

  NutritionLogEntry({
    required this.logId,
    required this.foodName,
    required this.mealType,
    required this.totalCalories,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.foods = const [],
  });

  factory NutritionLogEntry.fromJson(Map<String, dynamic> json) {
    return NutritionLogEntry(
      logId: (json['log_id'] ?? json['_id'] ?? '').toString(),
      foodName: json['food_name'] ?? json['name'] ?? 'Unknown',
      mealType: json['meal_type'] ?? '',
      totalCalories: (json['calories'] as num?)?.toInt() ??
          (json['total_calories'] as num?)?.toInt() ??
          0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      foods: (json['foods'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }
}

class NutritionPlan {
  String? id;
  String date;
  List<Meal> meals;
  final List<NutritionLogEntry> entries; // logged meals từ GET /{date}
  // 🔥 NEW: List Supplements
  List<Supplement> supplements;
  int currentWater;
  int targetWater;
  final int totalCaloriesConsumed;
  final int totalProteinConsumed;
  final int totalCarbsConsumed;
  final int totalFatConsumed;
  final int rolloverCalories;

  NutritionPlan({
    this.id,
    required this.date,
    required this.meals,
    this.entries = const [],
    this.supplements = const [], // Default empty
    this.currentWater = 0,
    this.targetWater = 2000,
    this.totalCaloriesConsumed = 0,
    this.totalProteinConsumed = 0,
    this.totalCarbsConsumed = 0,
    this.totalFatConsumed = 0,
    this.rolloverCalories = 0,
  });

  factory NutritionPlan.fromJson(Map<String, dynamic> json) {
    return NutritionPlan(
      id: json['_id'],
      date: json['date'] ?? '',
      currentWater: (json['current_water'] as num?)?.toInt() ?? 0,
      targetWater: (json['water_target'] as num?)?.toInt() ??
          (json['target_water'] as num?)?.toInt() ??
          2000,
      totalCaloriesConsumed: (json['total_calories'] as num?)?.toInt() ?? 0,
      totalProteinConsumed: (json['total_protein'] as num?)?.toInt() ?? 0,
      totalCarbsConsumed: (json['total_carbs'] as num?)?.toInt() ?? 0,
      totalFatConsumed: (json['total_fat'] as num?)?.toInt() ?? 0,
      rolloverCalories: (json['rollover_calories'] as num?)?.toInt() ?? 0,
      meals: (json['meals'] as List<dynamic>?)
              ?.map((e) => Meal.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      entries: (json['entries'] as List<dynamic>?)
              ?.map(
                  (e) => NutritionLogEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      supplements: (json['supplements'] as List<dynamic>?)
              ?.map((e) => Supplement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  NutritionPlan copyWith({
    String? id,
    String? date,
    List<Meal>? meals,
    List<NutritionLogEntry>? entries,
    List<Supplement>? supplements,
    int? currentWater,
    int? targetWater,
    int? totalCaloriesConsumed,
    int? totalProteinConsumed,
    int? totalCarbsConsumed,
    int? totalFatConsumed,
    int? rolloverCalories,
  }) {
    return NutritionPlan(
      id: id ?? this.id,
      date: date ?? this.date,
      meals: meals ?? this.meals,
      entries: entries ?? this.entries,
      supplements: supplements ?? this.supplements,
      currentWater: currentWater ?? this.currentWater,
      targetWater: targetWater ?? this.targetWater,
      totalCaloriesConsumed:
          totalCaloriesConsumed ?? this.totalCaloriesConsumed,
      totalProteinConsumed: totalProteinConsumed ?? this.totalProteinConsumed,
      totalCarbsConsumed: totalCarbsConsumed ?? this.totalCarbsConsumed,
      totalFatConsumed: totalFatConsumed ?? this.totalFatConsumed,
      rolloverCalories: rolloverCalories ?? this.rolloverCalories,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'current_water': currentWater,
      'target_water': targetWater,
      'meals': meals.map((e) => e.toJson()).toList(),
      'supplements': supplements.map((e) => e.toJson()).toList(),
    };
  }
}

// 🔥 NEW CLASS: Supplement
class Supplement {
  String? id;
  String name;
  double amount;
  String unit;
  String time;

  Supplement({
    this.id,
    required this.name,
    required this.amount,
    required this.unit,
    required this.time,
  });

  factory Supplement.fromJson(Map<String, dynamic> json) {
    return Supplement(
      id: json['id'],
      name: json['name'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] ?? 'viên',
      time: json['time'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'unit': unit,
      'time': time,
    };
  }
}

class DailyNutrition {
  final String date;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final int logCount;

  const DailyNutrition({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.logCount,
  });

  bool get hasData => logCount > 0;

  factory DailyNutrition.fromJson(Map<String, dynamic> json) => DailyNutrition(
        date: json['date'] as String,
        calories: (json['calories'] as num?)?.toDouble() ?? 0,
        protein: (json['protein'] as num?)?.toDouble() ?? 0,
        carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
        fat: (json['fat'] as num?)?.toDouble() ?? 0,
        logCount: (json['log_count'] as num?)?.toInt() ?? 0,
      );
}

class WeeklyReport {
  final String startDate;
  final String endDate;
  final int daysLogged;
  final List<DailyNutrition> daily;
  final MacroTargets weeklyTotals;
  final double avgCalories;
  final MacroTargets macroTargets;

  const WeeklyReport({
    required this.startDate,
    required this.endDate,
    required this.daysLogged,
    required this.daily,
    required this.weeklyTotals,
    required this.avgCalories,
    required this.macroTargets,
  });

  factory WeeklyReport.fromJson(Map<String, dynamic> json) {
    final totals = json['weekly_totals'] as Map<String, dynamic>? ?? {};
    final targets = json['macro_targets'] as Map<String, dynamic>? ?? {};
    final avgCal = json['daily_average'] as Map<String, dynamic>? ?? {};

    return WeeklyReport(
      startDate: json['start_date'] as String,
      endDate: json['end_date'] as String,
      daysLogged: (json['days_logged'] as num?)?.toInt() ?? 0,
      daily: (json['daily'] as List<dynamic>?)
              ?.map((e) => DailyNutrition.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      weeklyTotals: MacroTargets.fromJson(totals),
      avgCalories: (avgCal['calories'] as num?)?.toDouble() ?? 0,
      macroTargets: MacroTargets.fromJson(targets),
    );
  }
}

class Meal {
  String foodId;
  String name;
  int calories;
  double protein;
  double carbs;
  double fat;
  int weightGrams;
  String mealType;
  String time;
  bool isEaten;
  List<String> tags;
  String? image;
  List<Map<String, dynamic>> foodsList; // ← THÊM: toàn bộ foods trong bữa

  Meal({
    required this.foodId,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.weightGrams,
    required this.mealType,
    required this.time,
    this.isEaten = false,
    this.tags = const [],
    this.image,
    this.foodsList = const [],
  });

  factory Meal.fromJson(Map<String, dynamic> json) {
    final foods = json['foods'] as List<dynamic>?;
    final firstFood = (foods != null && foods.isNotEmpty)
        ? Map<String, dynamic>.from(foods[0] as Map)
        : json;

    final mealTotalCal = (json['total_calories'] as num?)?.toInt();
    final mealTotalPro = (json['total_protein'] as num?)?.toDouble();
    final mealTotalCarb = (json['total_carbs'] as num?)?.toDouble();
    final mealTotalFat = (json['total_fat'] as num?)?.toDouble();

    return Meal(
      foodId: firstFood['food_id'] ?? '',
      name: firstFood['name'] ?? json['name'] ?? 'Unknown Food',
      calories: mealTotalCal ?? (firstFood['calories'] as num?)?.toInt() ?? 0,
      protein: mealTotalPro ?? (firstFood['protein'] as num?)?.toDouble() ?? 0,
      carbs: mealTotalCarb ?? (firstFood['carbs'] as num?)?.toDouble() ?? 0,
      fat: mealTotalFat ?? (firstFood['fat'] as num?)?.toDouble() ?? 0,
      weightGrams: (firstFood['weight_grams'] as num?)?.toInt() ?? 100,
      mealType: json['meal_type'] ?? '',
      time: json['time'] ?? '',
      isEaten: json['isEaten'] ?? false,
      tags: List<String>.from(json['tags'] ?? []),
      image: firstFood['image'],
      foodsList:
          foods?.map((f) => Map<String, dynamic>.from(f as Map)).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'food_id': foodId,
      'name': name,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'weight_grams': weightGrams,
      'meal_type': mealType,
      'time': time,
      'isEaten': isEaten,
      'tags': tags,
      'image': image,
      'foods': foodsList,
    };
  }

  Meal copyWith({
    String? foodId,
    String? name,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    int? weightGrams,
    String? mealType,
    String? time,
    bool? isEaten,
    List<String>? tags,
    String? image,
    List<Map<String, dynamic>>? foodsList,
  }) {
    return Meal(
      foodId: foodId ?? this.foodId,
      name: name ?? this.name,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      weightGrams: weightGrams ?? this.weightGrams,
      mealType: mealType ?? this.mealType,
      time: time ?? this.time,
      isEaten: isEaten ?? this.isEaten,
      tags: tags ?? this.tags,
      image: image ?? this.image,
      foodsList: foodsList ?? this.foodsList,
    );
  }
}
