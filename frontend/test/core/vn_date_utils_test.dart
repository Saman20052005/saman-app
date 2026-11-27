import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/core/utils/vn_date_utils.dart';

void main() {
  group('vn_date_utils (UTC+7)', () {
    test('before UTC+7 midnight (16:59:59 UTC) stays on previous VN day', () {
      final utc = DateTime.utc(2026, 11, 26, 16, 59, 59);
      expect(vnTodayIsoDate(utc), '2026-11-26');
      expect(vnTodayDate(utc), DateTime(2026, 11, 26));
    });

    test('at UTC+7 midnight (17:00:00 UTC) rolls over to next VN day', () {
      final utc = DateTime.utc(2026, 11, 26, 17, 0, 0);
      expect(vnTodayIsoDate(utc), '2026-11-27');
      expect(vnTodayDate(utc), DateTime(2026, 11, 27));
    });

    test('after UTC+7 midnight (17:30:00 UTC) is on next VN day', () {
      final utc = DateTime.utc(2026, 11, 26, 17, 30, 0);
      expect(vnTodayIsoDate(utc), '2026-11-27');
    });

    test('year-end boundary rolls over cleanly to new year', () {
      final utc = DateTime.utc(2026, 12, 31, 17, 0, 0);
      expect(vnTodayIsoDate(utc), '2027-01-01');
      expect(vnTodayDate(utc), DateTime(2027, 1, 1));
    });

    test('single-digit month and day are zero-padded', () {
      final utc = DateTime.utc(2026, 1, 4, 18, 0, 0);
      expect(vnTodayIsoDate(utc), '2026-01-05');
      expect(vnTodayDate(utc), DateTime(2026, 1, 5));
    });
  });
}
