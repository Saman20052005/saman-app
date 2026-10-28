import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UnitSystem {
  metric,
  imperial,
}

class UnitConverter {
  UnitConverter._();

  // Standard constants:
  // 1 lb = 0.45359237 kg
  // 1 kg = 2.2046226218487757 lb
  // 1 inch = 2.54 cm
  // 1 foot = 12 inches = 30.48 cm
  static const double kgToLbMultiplier = 2.2046226218487757;
  static const double lbToKgMultiplier = 0.45359237;
  static const double cmPerInch = 2.54;
  static const double inchesPerFoot = 12.0;

  static double kgToLb(double kg) => kg * kgToLbMultiplier;
  static double lbToKg(double lb) => lb * lbToKgMultiplier;

  static double cmToInches(double cm) => cm / cmPerInch;
  static double inchesToCm(double inches) => inches * cmPerInch;

  static ({int feet, int inches}) cmToFeetAndInches(double cm) {
    if (cm <= 0) return (feet: 0, inches: 0);
    final totalInches = (cm / cmPerInch).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return (feet: feet, inches: inches);
  }

  static double feetAndInchesToCm(int feet, double inches) {
    final totalInches = (feet * 12) + inches;
    return totalInches * cmPerInch;
  }

  /// Formats exact decimal without precision loss (preserves raw strings like "168.12345")
  static String formatDecimal(double? val) {
    if (val == null) return '—';
    if (val % 1 == 0) {
      return val.toInt().toString();
    }
    return val.toString();
  }

  /// Formats weight according to the active unit system.
  /// Raw weight is always stored in kg.
  static String formatWeight(
    double? weightKg,
    UnitSystem unitSystem, {
    bool includeUnit = true,
  }) {
    if (weightKg == null) return '—';
    if (unitSystem == UnitSystem.imperial) {
      final lb = kgToLb(weightKg);
      final text = (lb % 1 == 0)
          ? lb.toInt().toString()
          : ((lb * 10).round() / 10).toString();
      return includeUnit ? '$text lb' : text;
    }
    final text = formatDecimal(weightKg);
    return includeUnit ? '$text kg' : text;
  }

  /// Formats height according to the active unit system.
  /// Raw height is always stored in cm.
  static String formatHeight(
    double? heightCm,
    UnitSystem unitSystem, {
    bool includeUnit = true,
  }) {
    if (heightCm == null) return '—';
    if (unitSystem == UnitSystem.imperial) {
      final ftIn = cmToFeetAndInches(heightCm);
      return "${ftIn.feet}'${ftIn.inches}\"";
    }
    final text = formatDecimal(heightCm);
    return includeUnit ? '$text cm' : text;
  }

  /// Formats workout external load according to the active unit system.
  static String formatWorkoutWeight(
    double weightKg,
    UnitSystem unitSystem, {
    bool includeUnit = true,
  }) {
    return formatWeight(weightKg, unitSystem, includeUnit: includeUnit);
  }

  /// Returns unit label for weight ('kg' or 'lb')
  static String weightUnitLabel(UnitSystem unitSystem) {
    return unitSystem == UnitSystem.imperial ? 'lb' : 'kg';
  }

  /// Returns unit label for height ('cm' or 'in')
  static String heightUnitLabel(UnitSystem unitSystem) {
    return unitSystem == UnitSystem.imperial ? 'in' : 'cm';
  }
}

class UnitNotifier extends StateNotifier<UnitSystem> {
  UnitNotifier([super.initial = UnitSystem.metric]) {
    _loadUnit();
  }

  static const String prefsKey = 'saman_unit_system';

  Future<void> _loadUnit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefsKey);
      if (saved == 'imperial') {
        state = UnitSystem.imperial;
      } else if (saved == 'metric') {
        state = UnitSystem.metric;
      }
    } catch (_) {
      // Fallback to default
    }
  }

  Future<void> setUnitSystem(UnitSystem unit) async {
    state = unit;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey,
        unit == UnitSystem.imperial ? 'imperial' : 'metric',
      );
    } catch (_) {}
  }
}

final unitProvider = StateNotifierProvider<UnitNotifier, UnitSystem>((ref) {
  return UnitNotifier();
});

