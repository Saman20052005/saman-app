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
    required this.per100g,
    required this.nutritionSource,
    required this.top3,
  });

  factory AIAnalysisResult.fromJson(Map<String, dynamic> json) {
    final nutrition = json['nutrition'] as Map<String, dynamic>? ?? {};
    final per100g = json['per_100g'] as Map<String, dynamic>? ?? {};

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
      per100g: per100g,
      nutritionSource: nutritionSource,
      top3: top3,
    );
  }
}
