import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health_ai_app/utils/auth_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/nutrition/data/repositories/nutrition_repository_impl.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'daily_story_controller_test.dart';

const waterDate = '2026-10-23';
final waterDay = DateTime.parse(waterDate);
const waterMeal = {
  'food_id': 'meal',
  'name': 'Rice',
  'calories': 130,
  'protein': 3,
  'carbs': 28,
  'fat': 0,
  'weight_grams': 100,
  'meal_type': 'lunch',
  'time': '12:00',
};

class WaterHarness extends FoodHarness {
  int amount = 500;
  int version = 2;
  int target = 2400;
  bool emptyMeals = false;
  final applied = <String>{};
  WaterHarness({super.onRequest});

  @override
  ResponseBody defaults(RequestOptions o) {
    if (o.path.endsWith('/generate-plan')) {
      return foodReply({
        'plan': {
          'date': waterDate,
          'meals': [waterMeal]
        }
      });
    }
    if (o.path.contains('/api/nutrition/daily/') ||
        (o.method == 'GET' &&
            o.path.endsWith('/$waterDate') &&
            !o.path.contains('stories') &&
            !o.path.contains('log-story'))) {
      return daily();
    }
    if (o.path.endsWith('/water')) {
      final body = o.data as Map;
      final key = body['idempotency_key'] as String?;
      if (key == null || applied.add(key)) {
        amount += body['delta_ml'] as int? ?? 0;
        version++;
      }
      return foodReply(
          {'amount_ml': amount, 'version': version, 'date': waterDate});
    }
    return super.defaults(o);
  }

  ResponseBody daily({int? ml, int? ver, String date = waterDate}) =>
      foodReply({
        'date': date,
        'current_water': ml ?? amount,
        'water_version': ver ?? version,
        'water_target': target,
        'meals': emptyMeals ? [] : [waterMeal],
        'entries': [],
        'total_calories': 0,
      });

  bool isDaily(RequestOptions o) =>
      o.method == 'GET' &&
      o.path.endsWith('/$waterDate') &&
      !o.path.contains('log-story');
  NutritionNotifier get water => container.read(nutritionProvider.notifier);
  AsyncValue get waterState => container.read(nutritionProvider);
  Future<void> load({bool refresh = false}) =>
      water.loadDailyPlan(waterDay, forceRefresh: refresh);
  Future<void> generate(bool smart) => smart
      ? water.generateSmartPlan(date: waterDay, mealCount: 3, style: 'optimal')
      : water.generateAutoPlan(waterDay,
          targetCalories: 2000, goal: 'maintain');
  List<RequestOptions> get waterWrites => requests
      .where((o) => o.method == 'POST' && o.path.endsWith('/water'))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real repository generation preserves daily water version and zero',
      () async {
    final h = WaterHarness()
      ..amount = 0
      ..version = 7;
    await h.start();
    addTearDown(h.close);
    final result = await NutritionRepositoryImpl()
        .generatePlan(dateStr: waterDate, goal: 'maintain');
    expect(result.currentWater, 0);
    expect(result.waterVersion, 7);
    expect(result.targetWater, 2400);
  });

  test(
      'confirmed delta survives failed reload with visible error, not false zero',
      () async {
    var fail = false;
    late WaterHarness h;
    h = WaterHarness(
        onRequest: (o) async => h.isDaily(o) && fail
            ? foodReply({'detail': 'unavailable'}, 503)
            : h.defaults(o));
    await h.start();
    addTearDown(h.close);
    await h.load();
    await h.water.addWater(250, date: waterDate);
    fail = true;
    await h.load(refresh: true);
    expect(h.waterState.hasError, true);
    expect(h.waterState.value?.currentWater, 750);
    expect(h.waterState.value?.waterVersion, 3);
    fail = false;
    await h.load(refresh: true);
    expect(h.waterState.hasError, false);
    expect(h.waterState.value?.currentWater, 750);
    expect(h.waterWrites.single.data['delta_ml'], 250);
    expect(h.waterWrites.single.data.containsKey('amount_ml'), false);
  });

  test('initial GET failure stays unknown/error without automatic POST',
      () async {
    late WaterHarness h;
    h = WaterHarness(
        onRequest: (o) async => h.isDaily(o)
            ? foodReply({'detail': 'unavailable'}, 503)
            : h.defaults(o));
    await h.start();
    addTearDown(h.close);
    await h.load();
    expect(h.waterState.hasError, true);
    expect(h.waterState.valueOrNull, isNull);
    expect(h.requests.where((o) => o.path.endsWith('/generate-plan')), isEmpty);
  });

  test(
      'late lower version cannot roll back current snapshot or cached snapshot',
      () async {
    final entered = Completer<void>();
    final lateReply = Completer<ResponseBody>();
    var hold = false;
    late WaterHarness h;
    h = WaterHarness(onRequest: (o) async {
      if (h.isDaily(o) && hold) {
        hold = false;
        entered.complete();
        return lateReply.future;
      }
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    await h.load();
    hold = true;
    final older = h.load(refresh: true);
    await entered.future;
    h.amount = 1000;
    h.version = 4;
    await h.load(refresh: true);
    lateReply.complete(h.daily(ml: 250, ver: 1));
    await older;
    expect(h.waterState.value?.currentWater, 1000);
    expect(h.waterState.value?.waterVersion, 4);
    await h.load();
    expect(h.waterState.value?.currentWater, 1000);
  });

  test('clearCache refresh retains confirmed water against older response',
      () async {
    final h = WaterHarness();
    await h.start();
    addTearDown(h.close);
    await h.load();
    await h.water.addWater(250, date: waterDate);
    h.water.clearCache();
    h.amount = 0;
    h.version = 0;
    await h.load(refresh: true);
    expect(h.waterState.value?.currentWater, 750);
    expect(h.waterState.value?.waterVersion, 3);
  });

  test('newer authoritative zero is accepted, not replaced by positive cache',
      () async {
    final h = WaterHarness();
    await h.start();
    addTearDown(h.close);
    await h.load();
    h.amount = 0;
    h.version = 3;
    await h.load(refresh: true);
    expect(h.waterState.value?.currentWater, 0);
    expect(h.waterState.value?.waterVersion, 3);
  });

  test('empty-day auto-generation retains version even with known zero',
      () async {
    final h = WaterHarness()
      ..amount = 0
      ..version = 8
      ..emptyMeals = true;
    await h.start();
    addTearDown(h.close);
    await h.load();
    expect(h.waterState.value?.currentWater, 0);
    expect(h.waterState.value?.waterVersion, 8);
    expect(h.waterState.value?.meals, isNotEmpty);
  });

  for (final smart in [false, true]) {
    test(
        '${smart ? 'smart' : 'auto'} regeneration keeps water version and target',
        () async {
      final h = WaterHarness();
      await h.start();
      addTearDown(h.close);
      await h.load();
      await h.generate(smart);
      expect(h.waterState.value?.currentWater, 500);
      expect(h.waterState.value?.waterVersion, 2);
      expect(h.waterState.value?.targetWater, 2400);
    });
    test(
        '${smart ? 'smart' : 'auto'} generation GET failure preserves snapshot and error',
        () async {
      var fail = false;
      late WaterHarness h;
      h = WaterHarness(
          onRequest: (o) async => h.isDaily(o) && fail
              ? foodReply({'detail': 'unavailable'}, 503)
              : h.defaults(o));
      await h.start();
      addTearDown(h.close);
      await h.load();
      fail = true;
      await h.generate(smart);
      expect(h.waterState.hasError, true);
      expect(h.waterState.value?.currentWater, 500);
      expect(h.waterState.value?.waterVersion, 2);
      expect(h.water.isMealPlanGenerating, false);
    });
  }

  for (final afterCommit in [false, true]) {
    test(
        'retry ${afterCommit ? 'lost response' : 'transport failure'} reuses key after reload',
        () async {
      var fail = true;
      late WaterHarness h;
      h = WaterHarness(onRequest: (o) async {
        if (o.path.endsWith('/water') && fail) {
          fail = false;
          if (afterCommit) h.defaults(o);
          throw DioException(
              requestOptions: o, type: DioExceptionType.connectionError);
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      await h.load();
      await expectLater(
          h.water.addWater(250, date: waterDate), throwsA(isA<DioException>()));
      final key = h.water.lastFailedWaterKey;
      expect(key, isNotEmpty);
      await h.load(refresh: true);
      await h.water.addWater(250, date: waterDate);
      expect(h.waterWrites.length, 2);
      expect(h.waterWrites.last.data['idempotency_key'], key);
      expect(h.amount, 750);
      expect(h.waterState.value?.currentWater, 750);
      expect(h.waterState.value?.waterVersion, 3);
    });
  }

  test('late write failure cannot roll back another selected date', () async {
    final entered = Completer<void>();
    final pending = Completer<ResponseBody>();
    late WaterHarness h;
    h = WaterHarness(onRequest: (o) async {
      if (o.path.endsWith('/water')) {
        entered.complete();
        return pending.future;
      }
      if (o.path.endsWith('/2026-10-22'))
        return h.daily(ml: 100, ver: 0, date: '2026-10-22');
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    await h.load();
    final write = h.water.addWater(250, date: waterDate);
    final observed = expectLater(write, throwsA(isA<Exception>()));
    await entered.future;
    await h.water.loadDailyPlan(DateTime(2026, 10, 22), forceRefresh: true);
    pending.complete(foodReply({'detail': 'failed'}, 503));
    await observed;
    expect(h.waterState.value?.date, '2026-10-22');
    expect(h.waterState.value?.currentWater, 100);
    expect(h.waterState.value?.waterVersion, 0);
  });

  for (final transition in ['A-B', 'A-B-A', 'dispose']) {
    for (final write in [false, true]) {
      test('late ${write ? 'write' : 'fetch'} rejected after $transition',
          () async {
        final entered = Completer<void>();
        final pending = Completer<ResponseBody>();
        var hold = false;
        late WaterHarness h;
        h = WaterHarness(onRequest: (o) async {
          if (hold && (write ? o.path.endsWith('/water') : h.isDaily(o))) {
            hold = false;
            entered.complete();
            return pending.future;
          }
          return h.defaults(o);
        });
        await h.start();
        addTearDown(h.close);
        await h.load();
        final old = h.water;
        hold = true;
        final operation = write
            ? old.addWater(250, date: waterDate)
            : old.loadDailyPlan(waterDay, forceRefresh: true);
        // Read methods expose errors in state; write methods propagate failures.
        final observed = write
            ? expectLater(operation, throwsA(isA<Exception>()))
            : operation;
        await entered.future;
        if (transition == 'dispose') {
          h.container.invalidate(nutritionProvider);
        } else {
          await h.switchAccount('test-account-B');
          if (transition == 'A-B-A') await h.switchAccount('test-account-A');
        }
        h.amount = 100;
        h.version = 0;
        await h.load(refresh: true);
        pending.complete(write
            ? foodReply({'amount_ml': 750, 'version': 3})
            : h.daily(ml: 900, ver: 9));
        await observed;
        expect(h.waterState.value?.currentWater, 100);
        expect(h.waterState.value?.waterVersion, 0);
        await h.load();
        expect(h.waterState.value?.currentWater, 100);
      });
    }
  }

  test('account switch at dispatch blocks old Water write before adapter',
      () async {
    final h = WaterHarness();
    await h.start();
    addTearDown(h.close);
    await h.load();
    var switched = false;
    final interceptor = InterceptorsWrapper(onRequest: (o, handler) async {
      if (o.path.endsWith('/water') && !switched) {
        switched = true;
        await h.switchAccount('test-account-B');
      }
      handler.next(o);
    });
    ApiClient.dio.interceptors.insert(1, interceptor);
    addTearDown(() => ApiClient.dio.interceptors.remove(interceptor));
    await expectLater(
        h.water.addWater(250, date: waterDate), throwsA(isA<Exception>()));
    expect(switched, true);
    expect(h.waterWrites, isEmpty);
  });

  test('reset-day does not reset Water version or accept late pre-reset fetch',
      () async {
    final entered = Completer<void>();
    final pending = Completer<ResponseBody>();
    var hold = false;
    late WaterHarness h;
    h = WaterHarness(onRequest: (o) async {
      if (hold && h.isDaily(o)) {
        hold = false;
        entered.complete();
        return pending.future;
      }
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    await h.load();
    hold = true;
    final old = h.load(refresh: true);
    await entered.future;
    h.amount = 750;
    h.version = 3;
    expect(await h.water.resetDay(waterDay), true);
    pending.complete(h.daily(ml: 0, ver: 0));
    await old;
    expect(h.waterState.value?.currentWater, 750);
    expect(h.waterState.value?.waterVersion, 3);
  });

  test('known zero at version zero is valid data', () async {
    final h = WaterHarness()
      ..amount = 0
      ..version = 0;
    await h.start();
    addTearDown(h.close);
    await h.load();
    expect(h.waterState.hasError, false);
    expect(h.waterState.value?.currentWater, 0);
    expect(h.waterState.value?.waterVersion, 0);
  });

  test(
      'acknowledged write with failed GET retries reload without a second POST',
      () async {
    var failRead = false;
    late WaterHarness h;
    h = WaterHarness(onRequest: (o) async {
      if (o.path.endsWith('/water')) {
        final result = h.defaults(o);
        failRead = true;
        return result;
      }
      if (h.isDaily(o) && failRead)
        return foodReply({'detail': 'unavailable'}, 503);
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    await h.load();
    await expectLater(
        h.water.addWater(250, date: waterDate),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('acknowledged'))));
    final key = h.water.lastFailedWaterKey;
    expect(h.waterState.hasError, true);
    expect(h.waterState.value?.currentWater, 750);
    expect(h.waterState.value?.waterVersion, 3);
    failRead = false;
    expect(await h.water.addWater(250, date: waterDate), key);
    expect(h.waterWrites.length, 1);
    expect(h.waterState.hasError, false);
    expect(h.waterState.value?.currentWater, 750);
  });

  test('explicit retry of acknowledged key never adds a second delta',
      () async {
    final h = WaterHarness();
    await h.start();
    addTearDown(h.close);
    await h.load();
    final key = await h.water.addWater(250, date: waterDate);
    expect(
        await h.water.addWater(250, date: waterDate, idempotencyKey: key), key);
    expect(h.waterWrites.length, 1);
    expect(h.amount, 750);
    expect(h.waterState.value?.currentWater, 750);
  });

  test('uncertain retry rejects changed amount without sending a new key',
      () async {
    late WaterHarness h;
    h = WaterHarness(onRequest: (o) async {
      if (o.path.endsWith('/water'))
        throw DioException(
            requestOptions: o, type: DioExceptionType.connectionError);
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    await h.load();
    await expectLater(
        h.water.addWater(250, date: waterDate), throwsA(isA<DioException>()));
    await expectLater(
        h.water.addWater(500, date: waterDate), throwsA(isA<StateError>()));
    expect(h.waterWrites.length, 1);
  });

  for (final firstFails in [false, true]) {
    test(
        'concurrent deltas preserve exact total when first ${firstFails ? 'fails late' : 'succeeds'}',
        () async {
      final entered = Completer<void>();
      final pending = [Completer<ResponseBody>(), Completer<ResponseBody>()];
      var writes = 0;
      late WaterHarness h;
      h = WaterHarness(onRequest: (o) async {
        if (o.path.endsWith('/water')) {
          final i = writes++;
          if (writes == 2) entered.complete();
          return pending[i].future;
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      await h.load();
      final first = h.water.addWater(250, date: waterDate);
      final observedFirst =
          firstFails ? expectLater(first, throwsA(isA<DioException>())) : first;
      final second = h.water.addWater(250, date: waterDate);
      await entered.future;
      if (firstFails) {
        pending[1].complete(h.defaults(h.waterWrites[1]));
        await second;
        pending[0].complete(foodReply({'detail': 'failed'}, 503));
        await observedFirst;
      } else {
        pending[0].complete(h.defaults(h.waterWrites[0]));
        await observedFirst;
        pending[1].complete(h.defaults(h.waterWrites[1]));
        await second;
      }
      expect(h.amount, firstFails ? 750 : 1000);
      expect(h.waterState.value?.currentWater, h.amount);
      expect(h.waterState.value?.waterVersion, firstFails ? 3 : 4);
      expect(h.waterWrites[0].data['idempotency_key'],
          isNot(h.waterWrites[1].data['idempotency_key']));
    });
  }

  test(
      '409 replaces provisional total with authoritative water even at older version',
      () async {
    late WaterHarness h;
    h = WaterHarness(
        onRequest: (o) async => o.path.endsWith('/water')
            ? foodReply({'detail': 'conflict'}, 409)
            : h.defaults(o));
    await h.start();
    addTearDown(h.close);
    await h.load();
    await expectLater(h.water.updateWater(1000, date: waterDate),
        throwsA(isA<DioException>()));
    expect(h.waterState.value?.currentWater, 500);
    expect(h.waterState.value?.waterVersion, 2);
    expect(h.waterWrites.single.data['version'], 2);
    await h.load();
    expect(h.waterState.value?.currentWater, 500);
  });

  test('token change without cache recreation never serves prior owner cache',
      () async {
    final h = WaterHarness();
    await h.start();
    addTearDown(h.close);
    await h.load();
    await const FlutterSecureStorage()
        .write(key: 'auth_token', value: 'test-account-B');
    h.amount = 0;
    h.version = 0;
    await h.load();
    expect(h.waterState.value?.currentWater, 0);
    expect(h.waterState.value?.waterVersion, 0);
    final daily = h.requests.where(h.isDaily).toList();
    expect(daily.last.headers['Authorization'], 'Bearer test-account-B');
  });

  for (final write in [false, true]) {
    test(
        'late ${write ? 'write' : 'fetch'} cannot repopulate cache after real logout',
        () async {
      final entered = Completer<void>();
      final pending = Completer<ResponseBody>();
      var hold = false;
      late WaterHarness h;
      h = WaterHarness(onRequest: (o) async {
        if (hold && (write ? o.path.endsWith('/water') : h.isDaily(o))) {
          hold = false;
          entered.complete();
          return pending.future;
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      await h.load();
      hold = true;
      final operation = write
          ? h.water.addWater(250, date: waterDate)
          : h.load(refresh: true);
      final observed =
          write ? expectLater(operation, throwsA(isA<Exception>())) : operation;
      await entered.future;
      await AuthHelper.logout(h.container);
      pending.complete(write
          ? foodReply({'amount_ml': 750, 'version': 3})
          : h.daily(ml: 900, ver: 9));
      await observed;
      expect(h.waterState.valueOrNull, isNull);
      await h.load();
      expect(h.waterState.valueOrNull, isNull);
      expect(h.waterState.hasError, true);
    });
  }

  test(
      'generation account switch rejects result and never starts followup daily GET',
      () async {
    final entered = Completer<void>();
    final pending = Completer<ResponseBody>();
    late WaterHarness h;
    h = WaterHarness(onRequest: (o) async {
      if (o.path.endsWith('/generate-plan')) {
        entered.complete();
        return pending.future;
      }
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    await h.load();
    final getCount = h.requests.where(h.isDaily).length;
    final generation = h.generate(true);
    await entered.future;
    await h.switchAccount('test-account-B');
    pending.complete(foodReply({
      'plan': {
        'date': waterDate,
        'meals': [waterMeal]
      }
    }));
    await generation;
    expect(h.requests.where(h.isDaily).length, getCount);
    expect(h.waterState.valueOrNull, isNull);
  });

  test('multiple uncertain operations retain both original retry keys',
      () async {
    var attempts = 0;
    late WaterHarness h;
    h = WaterHarness(onRequest: (o) async {
      if (o.path.endsWith('/water') && attempts++ < 2) {
        throw DioException(
            requestOptions: o, type: DioExceptionType.connectionError);
      }
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    await h.load();
    final first = h.water.addWater(250, date: waterDate);
    final observedFirst = expectLater(first, throwsA(isA<DioException>()));
    final second = h.water.addWater(250, date: waterDate);
    await Future.wait(
        [observedFirst, expectLater(second, throwsA(isA<DioException>()))]);
    final originalKeys =
        h.waterWrites.map((o) => o.data['idempotency_key']).toSet();
    expect(originalKeys.length, 2);
    await h.water.addWater(250, date: waterDate);
    await h.water.addWater(250, date: waterDate);
    expect(h.waterWrites.length, 4);
    expect(h.waterWrites.map((o) => o.data['idempotency_key']).toSet(),
        originalKeys);
    expect(h.amount, 1000);
    expect(h.waterState.value?.currentWater, 1000);
  });

  test('controller recreation retries explicit old key without inflating water',
      () async {
    final h = WaterHarness();
    await h.start();
    addTearDown(h.close);
    await h.load();
    final key = await h.water.addWater(250, date: waterDate);
    h.container.invalidate(nutritionProvider);
    await h.load();
    await h.water.addWater(250, date: waterDate, idempotencyKey: key);
    expect(h.waterWrites.length, 2);
    expect(h.waterWrites.last.data['idempotency_key'], key);
    expect(h.amount, 750);
    expect(h.waterState.value?.currentWater, 750);
    expect(h.waterState.value?.waterVersion, 3);
  });
}
