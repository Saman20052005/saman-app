// lib/models/ai_analysis_result.dart

class FoodPrediction {
  final String label;
  final String foodName;
  final double confidence;

  const FoodPrediction({
    required this.label,
    required this.foodName,
    required this.confidence,
  });

  factory FoodPrediction.fromJson(Map<String, dynamic> json) => FoodPrediction(
        label: json['label'] as String,
        foodName: json['food_name'] as String,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class IngredientItem {
  final String name;
  final double portionGrams;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double confidence;

  const IngredientItem({
    required this.name,
    required this.portionGrams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.confidence,
  });

  factory IngredientItem.fromJson(Map<String, dynamic> json) => IngredientItem(
        name: json['name']?.toString() ?? '',
        portionGrams: (json['portion_grams'] as num?)?.toDouble() ?? 0,
        calories: (json['calories'] as num?)?.toDouble() ?? 0,
        protein: (json['protein'] as num?)?.toDouble() ?? 0,
        carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
        fat: (json['fat'] as num?)?.toDouble() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'portion_grams': portionGrams,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'confidence': confidence,
      };
}

class AIAnalysisResult {
  final String foodName;
  final String foodLabel;
  final double confidence;
  final bool lowConfidence;
  final double grams;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double? fiber;
  final List<IngredientItem> ingredients;
  final List<String> healthInsights;
  final Map<String, dynamic> per100g;
  final String nutritionSource;
  final List<FoodPrediction> top3;

  const AIAnalysisResult({
    required this.foodName,
    required this.foodLabel,
    required this.confidence,
    required this.lowConfidence,
    required this.grams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber,
    this.ingredients = const [],
    this.healthInsights = const [],
    required this.per100g,
    required this.nutritionSource,
    required this.top3,
  });

  factory AIAnalysisResult.fromJson(Map<String, dynamic> json) {
    final nutrition = json['nutrition'] as Map<String, dynamic>? ?? {};
    final per100g = json['per_100g'] as Map<String, dynamic>? ?? {};
    final totalNutrition =
        json['total_nutrition'] as Map<String, dynamic>? ?? {};

    return AIAnalysisResult(
      foodName: json['food_name'] as String? ?? 'Unknown',
      foodLabel: json['food_label'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      lowConfidence: json['low_confidence'] as bool? ?? false,
      grams: (json['grams'] as num?)?.toDouble() ?? 100.0,
      calories: (nutrition['calories'] as num?)?.toDouble() ?? 0.0,
      protein: (nutrition['protein'] as num?)?.toDouble() ?? 0.0,
      carbs: (nutrition['carbs'] as num?)?.toDouble() ?? 0.0,
      fat: (nutrition['fat'] as num?)?.toDouble() ?? 0.0,
      fiber: (json['fiber'] as num?)?.toDouble() ??
          (nutrition['fiber'] as num?)?.toDouble() ??
          (totalNutrition['fiber'] as num?)?.toDouble(),
      ingredients: (json['ingredients'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(IngredientItem.fromJson)
          .toList(),
      healthInsights: (json['health_insights'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      per100g: per100g,
      nutritionSource: json['nutrition_source'] as String? ?? 'unknown',
      top3: (json['top3_predictions'] as List<dynamic>? ?? [])
          .map((e) => FoodPrediction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  AIAnalysisResult withGrams(double newGrams) {
    if (per100g.isEmpty) return this;
    final ratio = newGrams / 100.0;
    return AIAnalysisResult(
      foodName: foodName,
      foodLabel: foodLabel,
      confidence: confidence,
      lowConfidence: lowConfidence,
      grams: newGrams,
      calories: ((per100g['calories'] as num?)?.toDouble() ?? calories) * ratio,
      protein: ((per100g['protein'] as num?)?.toDouble() ?? protein) * ratio,
      carbs: ((per100g['carbs'] as num?)?.toDouble() ?? carbs) * ratio,
      fat: ((per100g['fat'] as num?)?.toDouble() ?? fat) * ratio,
      fiber: fiber == null
          ? null
          : ((per100g['fiber'] as num?)?.toDouble() ??
                  (grams == 0 ? fiber! : fiber! / grams * 100)) *
              ratio,
      ingredients: ingredients,
      healthInsights: healthInsights,
      per100g: per100g,
      nutritionSource: nutritionSource,
      top3: top3,
    );
  }

  AIAnalysisResult withLabel(FoodPrediction selected) {
    return AIAnalysisResult(
      foodName: selected.foodName,
      foodLabel: selected.label,
      confidence: selected.confidence,
      lowConfidence: selected.confidence < 0.40,
      grams: grams,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fiber,
      ingredients: ingredients,
      healthInsights: healthInsights,
      per100g: per100g,
      nutritionSource: nutritionSource,
      top3: top3,
    );
  }

  AIAnalysisResult copyWith({
    String? foodName,
    String? foodLabel,
    double? confidence,
    bool? lowConfidence,
    double? grams,
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? fiber,
    bool clearFiber = false,
    List<IngredientItem>? ingredients,
    List<String>? healthInsights,
    Map<String, dynamic>? per100g,
    String? nutritionSource,
    List<FoodPrediction>? top3,
  }) =>
      AIAnalysisResult(
        foodName: foodName ?? this.foodName,
        foodLabel: foodLabel ?? this.foodLabel,
        confidence: confidence ?? this.confidence,
        lowConfidence: lowConfidence ?? this.lowConfidence,
        grams: grams ?? this.grams,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        fiber: clearFiber ? null : (fiber ?? this.fiber),
        ingredients: ingredients ?? this.ingredients,
        healthInsights: healthInsights ?? this.healthInsights,
        per100g: per100g ?? this.per100g,
        nutritionSource: nutritionSource ?? this.nutritionSource,
        top3: top3 ?? this.top3,
      );

  Map<String, dynamic> toJson() => {
        'food_name': foodName,
        'food_label': foodLabel,
        'confidence': confidence,
        'low_confidence': lowConfidence,
        'grams': grams,
        'nutrition': {
          'calories': calories,
          'protein': protein,
          'carbs': carbs,
          'fat': fat,
          if (fiber != null) 'fiber': fiber,
        },
        if (fiber != null) 'fiber': fiber,
        'per_100g': per100g,
        'nutrition_source': nutritionSource,
        'top3_predictions': top3
            .map((prediction) => {
                  'label': prediction.label,
                  'food_name': prediction.foodName,
                  'confidence': prediction.confidence,
                })
            .toList(),
        'ingredients':
            ingredients.map((ingredient) => ingredient.toJson()).toList(),
        'health_insights': healthInsights,
      };
}
