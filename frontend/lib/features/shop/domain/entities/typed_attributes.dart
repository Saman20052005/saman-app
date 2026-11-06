import 'package:equatable/equatable.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. Dụng Cụ Tập (EquipmentAttributes)
// ─────────────────────────────────────────────────────────────────────────────

class EquipmentAttributes extends Equatable {
  final String primaryMaterial;
  final String? gripType;
  final double? lengthCm;
  final double? widthCm;
  final double? thicknessMm;
  final double? weightKg;
  final double? maxLoadCapacityKg;
  final String? resistanceRange;
  final String? usageEnvironment;

  const EquipmentAttributes({
    required this.primaryMaterial,
    this.gripType,
    this.lengthCm,
    this.widthCm,
    this.thicknessMm,
    this.weightKg,
    this.maxLoadCapacityKg,
    this.resistanceRange,
    this.usageEnvironment,
  });

  @override
  List<Object?> get props => [
        primaryMaterial,
        gripType,
        lengthCm,
        widthCm,
        thicknessMm,
        weightKg,
        maxLoadCapacityKg,
        resistanceRange,
        usageEnvironment,
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Thời Trang Thể Thao (ApparelAttributes)
// ─────────────────────────────────────────────────────────────────────────────

class ApparelColorSwatch extends Equatable {
  final String name;
  final String hexColor;

  const ApparelColorSwatch({
    required this.name,
    required this.hexColor,
  });

  @override
  List<Object?> get props => [name, hexColor];
}

class ApparelAttributes extends Equatable {
  final String fabricComposition;
  final String fitType;
  final String genderTarget;
  final List<String> sizePreviewList;
  final List<ApparelColorSwatch> colorSwatches;
  final List<String> technologyTags;
  final List<String> careInstructions;

  ApparelAttributes({
    required this.fabricComposition,
    required this.fitType,
    required this.genderTarget,
    required List<String> sizePreviewList,
    List<ApparelColorSwatch> colorSwatches = const [],
    List<String> technologyTags = const [],
    List<String> careInstructions = const [],
  })  : sizePreviewList = List.unmodifiable(sizePreviewList),
        colorSwatches = List.unmodifiable(colorSwatches),
        technologyTags = List.unmodifiable(technologyTags),
        careInstructions = List.unmodifiable(careInstructions);

  @override
  List<Object?> get props => [
        fabricComposition,
        fitType,
        genderTarget,
        sizePreviewList,
        colorSwatches,
        technologyTags,
        careInstructions,
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Thực Phẩm & Đồ Uống (FoodAttributes)
// ─────────────────────────────────────────────────────────────────────────────

enum AllergenStatus {
  unknown,
  freeOfDeclaredAllergens,
  containsAllergens,
}

class MacroNutrients extends Equatable {
  final int? energyKcal;
  final double? proteinGrams;
  final double? carbohydratesGrams;
  final double? totalFatGrams;
  final double? saturatedFatGrams;
  final double? dietaryFiberGrams;
  final double? sugarsGrams;
  final int? sodiumMg;

  const MacroNutrients({
    this.energyKcal,
    this.proteinGrams,
    this.carbohydratesGrams,
    this.totalFatGrams,
    this.saturatedFatGrams,
    this.dietaryFiberGrams,
    this.sugarsGrams,
    this.sodiumMg,
  });

  @override
  List<Object?> get props => [
        energyKcal,
        proteinGrams,
        carbohydratesGrams,
        totalFatGrams,
        saturatedFatGrams,
        dietaryFiberGrams,
        sugarsGrams,
        sodiumMg,
      ];
}

class FoodAttributes extends Equatable {
  final String netWeightText;
  final String servingSizeText;
  final int? servingsPerContainer;
  final MacroNutrients? perServingMacros;
  final MacroNutrients? per100gMacros;
  final String ingredientsText;
  final AllergenStatus allergenStatus;
  final List<String> allergenList;
  final String? storageInstructions;
  final String? shelfLifeText;

  FoodAttributes({
    required this.netWeightText,
    required this.servingSizeText,
    this.servingsPerContainer,
    this.perServingMacros,
    this.per100gMacros,
    required this.ingredientsText,
    this.allergenStatus = AllergenStatus.unknown,
    List<String> allergenList = const [],
    this.storageInstructions,
    this.shelfLifeText,
  }) : allergenList = List.unmodifiable(allergenList);

  @override
  List<Object?> get props => [
        netWeightText,
        servingSizeText,
        servingsPerContainer,
        perServingMacros,
        per100gMacros,
        ingredientsText,
        allergenStatus,
        allergenList,
        storageInstructions,
        shelfLifeText,
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Thực Phẩm Bổ Sung (SupplementAttributes)
// ─────────────────────────────────────────────────────────────────────────────

enum SupplementForm {
  powder,
  capsule,
  tablet,
  effervescentTablet,
  liquid,
}

class ActiveIngredient extends Equatable {
  final String name;
  final String amountPerServing;

  const ActiveIngredient({
    required this.name,
    required this.amountPerServing,
  });

  @override
  List<Object?> get props => [name, amountPerServing];
}

class SupplementAttributes extends Equatable {
  final SupplementForm form;
  final String netWeightText;
  final String servingSizeText;
  final int servingsPerContainer;
  final List<ActiveIngredient> activeIngredients;
  final String suggestedUse;
  final String safetyAdvisory;
  final bool isProhibitedForMinors;

  SupplementAttributes({
    required this.form,
    required this.netWeightText,
    required this.servingSizeText,
    required this.servingsPerContainer,
    required List<ActiveIngredient> activeIngredients,
    required this.suggestedUse,
    required this.safetyAdvisory,
    this.isProhibitedForMinors = false,
  }) : activeIngredients = List.unmodifiable(activeIngredients);

  @override
  List<Object?> get props => [
        form,
        netWeightText,
        servingSizeText,
        servingsPerContainer,
        activeIngredients,
        suggestedUse,
        safetyAdvisory,
        isProhibitedForMinors,
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Phục Hồi & Sinh Hoạt (LifestyleAttributes)
// ─────────────────────────────────────────────────────────────────────────────

class LifestyleAttributes extends Equatable {
  final String primaryMaterial;
  final int? capacityMl;
  final bool isDishwasherSafe;
  final bool isMicrowaveSafe;
  final bool isBpaFree;
  final int? keepColdHours;
  final int? keepHotHours;
  final int? compartmentCount;
  final List<String> includedAccessories;

  LifestyleAttributes({
    required this.primaryMaterial,
    this.capacityMl,
    this.isDishwasherSafe = false,
    this.isMicrowaveSafe = false,
    this.isBpaFree = true,
    this.keepColdHours,
    this.keepHotHours,
    this.compartmentCount,
    List<String> includedAccessories = const [],
  }) : includedAccessories = List.unmodifiable(includedAccessories);

  @override
  List<Object?> get props => [
        primaryMaterial,
        capacityMl,
        isDishwasherSafe,
        isMicrowaveSafe,
        isBpaFree,
        keepColdHours,
        keepHotHours,
        compartmentCount,
        includedAccessories,
      ];
}

