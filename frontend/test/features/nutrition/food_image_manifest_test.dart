import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/nutrition/data/food_image_manifest.dart';

void main() {
  group('food image manifest', () {
    test('covers 204 canonical foods with unique stable ids', () {
      expect(kFoodImageIdByName.length, 204);
      expect(kFoodImageIdByName.values.toSet().length, 204);
    });

    test('every mapped active asset file exists and is a readable JPEG; pending items return null', () {
      final missing = <String>[];
      final invalid = <String>[];
      var activeCount = 0;
      var pendingCount = 0;

      for (final name in kFoodImageIdByName.keys) {
        final path = foodImageAssetFor(name);
        if (path == null) {
          expect(isFoodImagePending(name), isTrue,
              reason: 'Foods without assets must be in kPendingFoodIds: $name');
          pendingCount++;
          continue;
        }

        activeCount++;
        final file = File(path);
        if (!file.existsSync()) {
          missing.add('$name -> $path');
          continue;
        }
        final bytes = file.readAsBytesSync();
        final isJpeg = bytes.length > 3 &&
            bytes[0] == 0xFF &&
            bytes[1] == 0xD8 &&
            bytes[2] == 0xFF;
        if (!isJpeg) invalid.add(path);
      }

      expect(activeCount, 198, reason: 'Expected 198 active curated food assets');
      expect(pendingCount, 6, reason: 'Expected exactly 6 pending food items');
      expect(missing, isEmpty,
          reason: 'Missing image files (${missing.length}/198)');
      expect(invalid, isEmpty, reason: 'Not valid JPEG files');
    });

    test('lookup is exact-name only (no substring/fuzzy matching)', () {
      expect(foodImageAssetFor('Ức gà luộc/hấp'),
          'assets/images/nutrition/food_uc_ga_luoc_hap.jpg');
      expect(foodImageAssetFor('  Phở bò  '),
          'assets/images/nutrition/food_pho_bo.jpg');
      expect(foodImageAssetFor('Ức gà'), isNull);
      expect(foodImageAssetFor('Grilled Chicken'), isNull);
      expect(foodImageAssetFor('pho bo'), isNull);
    });
  });
}
