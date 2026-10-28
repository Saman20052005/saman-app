import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/services/unit_converter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnitConverter - Conversion & Formatting Integrity', () {
    test('Weight conversion: 1 kg = 2.20462 lb and roundtrip consistency', () {
      const kg = 70.0;
      final lb = UnitConverter.kgToLb(kg);
      expect(lb, closeTo(154.32, 0.05));

      final roundtripKg = UnitConverter.lbToKg(lb);
      expect(roundtripKg, closeTo(kg, 0.0001));
    });

    test('Height conversion: cm <-> inches and feet-inches conversion', () {
      const cm = 171.0;
      final inches = UnitConverter.cmToInches(cm);
      expect(inches, closeTo(67.32, 0.05));

      final ftIn = UnitConverter.cmToFeetAndInches(cm);
      expect(ftIn.feet, equals(5));
      expect(ftIn.inches, equals(7)); // 171cm -> 5'7"

      final backCm = UnitConverter.feetAndInchesToCm(ftIn.feet, ftIn.inches.toDouble());
      expect(backCm, closeTo(170.18, 0.5));
    });

    test('formatDecimal preserves exact precision and removes trailing .0 for whole numbers', () {
      expect(UnitConverter.formatDecimal(70.0), equals('70'));
      expect(UnitConverter.formatDecimal(72.5), equals('72.5'));
      expect(UnitConverter.formatDecimal(168.12345), equals('168.12345'));
      expect(UnitConverter.formatDecimal(null), equals('—'));
    });

    test('formatWeight formats Metric (kg) and Imperial (lb) accurately', () {
      expect(UnitConverter.formatWeight(70.0, UnitSystem.metric), equals('70 kg'));
      expect(UnitConverter.formatWeight(72.5, UnitSystem.metric), equals('72.5 kg'));
      expect(UnitConverter.formatWeight(68.0, UnitSystem.imperial), equals('149.9 lb'));
      expect(UnitConverter.formatWeight(null, UnitSystem.metric), equals('—'));
      expect(UnitConverter.formatWeight(null, UnitSystem.imperial), equals('—'));
    });

    test('formatHeight formats Metric (cm) and Imperial (ft/in) accurately', () {
      expect(UnitConverter.formatHeight(171.0, UnitSystem.metric), equals('171 cm'));
      expect(UnitConverter.formatHeight(175.5, UnitSystem.metric), equals('175.5 cm'));
      expect(UnitConverter.formatHeight(171.0, UnitSystem.imperial), equals("5'7\""));
      expect(UnitConverter.formatHeight(180.0, UnitSystem.imperial), equals("5'11\""));
      expect(UnitConverter.formatHeight(null, UnitSystem.metric), equals('—'));
      expect(UnitConverter.formatHeight(null, UnitSystem.imperial), equals('—'));
    });

    test('UnitNotifier loads and persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'saman_unit_system': 'imperial'});

      final notifier = UnitNotifier();
      // Wait for async load
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state, equals(UnitSystem.imperial));

      await notifier.setUnitSystem(UnitSystem.metric);
      expect(notifier.state, equals(UnitSystem.metric));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saman_unit_system'), equals('metric'));
    });
  });
}

