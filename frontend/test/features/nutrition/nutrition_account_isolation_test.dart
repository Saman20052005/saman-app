import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/providers/daily_story_provider.dart';
import 'package:health_ai_app/services/nutrition_service.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/utils/auth_helper.dart';
import 'daily_story_controller_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  accountContinuityTests();
  for (final transition in ['logout', 'A-B', 'A-B-A', 'dispose']) {
    test('late Chat analysis discarded after $transition', () async {
      final entered = Completer<void>();
      final pending = Completer<ResponseBody>();
      late FoodHarness h;
      h = FoodHarness(onRequest: (o) async {
        if (o.path.endsWith('/analyze')) {
          entered.complete();
          return pending.future;
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      final chat = h.container.read(chatControllerProvider.notifier);
      final analysis = chat.analyzeFoodPhoto(h.photo());
      await entered.future;
      if (transition == 'logout') {
        await AuthHelper.logout(h.container);
      } else if (transition == 'dispose') {
        h.container.invalidate(chatControllerProvider);
      } else {
        await h.switchAccount('test-account-B');
        if (transition == 'A-B-A') await h.switchAccount('test-account-A');
      }
      pending.complete(foodReply(foodPayload));
      await analysis;
      expect(
          h.container.read(chatControllerProvider).foodAnalysisState, isNull);
      expect(h.writes('/log-story'), 0);
      expect(h.writes('/logs'), 0);
    });
  }

  for (final transition in ['A-B', 'A-B-A', 'dispose']) {
    test('late Nutrition analysis rejected after $transition', () async {
      final entered = Completer<void>();
      final pending = Completer<ResponseBody>();
      late FoodHarness h;
      h = FoodHarness(onRequest: (o) async {
        if (o.path.endsWith('/analyze')) {
          entered.complete();
          return pending.future;
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      final analysis = h.controller.analyzeImage(h.photo());
      final observed =
          expectLater(analysis, throwsA(isA<NutritionSessionChanged>()));
      await entered.future;
      if (transition == 'dispose') {
        h.container.invalidate(dailyStoryControllerProvider(FoodHarness.date));
        await h.container
            .read(dailyStoryControllerProvider(FoodHarness.date).future);
      } else {
        await h.switchAccount('test-account-B');
        if (transition == 'A-B-A') await h.switchAccount('test-account-A');
      }
      pending.complete(foodReply(foodPayload));
      await observed;
    });
  }

  for (final stage in ['story', 'meal']) {
    test(
        'account change during $stage persistence never continues/applies to B',
        () async {
      final entered = Completer<void>();
      final pending = Completer<ResponseBody>();
      late FoodHarness h;
      h = FoodHarness(onRequest: (o) async {
        if (o.method == 'POST' &&
            o.path.endsWith(stage == 'story' ? '/log-story' : '/logs')) {
          entered.complete();
          return pending.future;
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      final photo = h.photo();
      final data = mealData();
      final owner = await h.container.read(nutritionSessionProvider).capture();
      final save =
          h.controller.confirmLog(data, imageFile: photo, session: owner);
      final observed =
          expectLater(save, throwsA(isA<NutritionSessionChanged>()));
      await entered.future;
      await h.switchAccount('test-account-B');
      pending.complete(foodReply({'log_id': 'story-A', 'status': 'saved'}));
      await observed;
      expect(h.writes('/logs'), stage == 'story' ? 0 : 1);
      await expectLater(
          h.controller.confirmLog(data, imageFile: photo, session: owner),
          throwsA(isA<NutritionSessionChanged>()));
      expect(h.writes('/log-story'), 1);
    });
  }

  test('provider recreation reuses a confirmed Story after in-flight disposal',
      () async {
    final entered = Completer<void>();
    final pending = Completer<ResponseBody>();
    late FoodHarness h;
    h = FoodHarness(onRequest: (o) async {
      if (o.method == 'POST' && o.path.endsWith('/log-story')) {
        entered.complete();
        return pending.future;
      }
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    final data = mealData();
    final photo = h.photo();
    final save = h.controller.confirmLog(data, imageFile: photo);
    final observed = expectLater(save, throwsA(isA<NutritionSessionChanged>()));
    await entered.future;
    h.container.invalidate(dailyStoryControllerProvider(FoodHarness.date));
    await h.container
        .read(dailyStoryControllerProvider(FoodHarness.date).future);
    // A second controller cannot write while the first request is unresolved.
    await expectLater(h.controller.confirmLog(data, imageFile: photo),
        throwsA(isA<ConfirmLogException>()));
    pending.complete(foodReply({'log_id': 'story-1'}));
    await observed;
    await h.controller.confirmLog(data, imageFile: photo);
    expect(h.writes('/log-story'), 1);
    expect(h.writes('/logs'), 1);
  });

  test('new account request uses new auth header without prior progress',
      () async {
    final h = FoodHarness();
    await h.start();
    addTearDown(h.close);
    final photo = h.photo();
    final data = mealData();
    await h.controller.confirmLog(data, imageFile: photo);
    await h.switchAccount('test-account-B');
    await h.controller.analyzeImage(photo, mode: 'standard');
    await h.controller.confirmLog(data, imageFile: photo);
    final writes = h.requests.where((o) => o.method == 'POST').toList();
    expect(writes.first.headers['Authorization'], 'Bearer test-account-A');
    expect(writes.last.headers['Authorization'], 'Bearer test-account-B');
    expect(h.writes('/log-story'), 2);
    expect(h.writes('/logs'), 2);
  });
  test(
      'account switch between auth interceptor and dispatch blocks old request',
      () async {
    final h = FoodHarness();
    await h.start();
    addTearDown(h.close);
    var switched = false;
    final interceptor =
        InterceptorsWrapper(onRequest: (options, handler) async {
      if (options.path.endsWith('/analyze') && !switched) {
        switched = true;
        await h.switchAccount('test-account-B');
      }
      handler.next(options);
    });
    // The shared auth interceptor has run; the Food dispatch guard runs next.
    ApiClient.dio.interceptors.insert(1, interceptor);
    addTearDown(() => ApiClient.dio.interceptors.remove(interceptor));
    await expectLater(h.controller.analyzeImage(h.photo()),
        throwsA(isA<NutritionSessionChanged>()));
    expect(switched, true);
    expect(h.requests.where((o) => o.path.endsWith('/analyze')), isEmpty);
    expect(h.writes('/log-story'), 0);
    expect(h.writes('/logs'), 0);
  });
}

void accountContinuityTests() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final stage in ['story', 'meal']) {
    test('$stage uncertainty survives real logout/login A-B-A', () async {
      late FoodHarness h;
      h = FoodHarness(onRequest: (o) async {
        if (o.method == 'POST' &&
            o.headers['Authorization'] == 'Bearer test-account-A' &&
            o.path.endsWith(stage == 'story' ? '/log-story' : '/logs')) {
          throw DioException(
              requestOptions: o, type: DioExceptionType.receiveTimeout);
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      final photo = h.photo();
      final data = mealData();
      final unknown = isA<ConfirmLogException>()
          .having((e) => e.outcomeUnknown, 'uncertain', true)
          .having((e) => e.canRetry, 'blind retry', false);
      await expectLater(
          h.controller.confirmLog(data, imageFile: photo), throwsA(unknown));
      await h.switchAccount('test-account-B');
      expect(h.container.read(profileProvider).confirmedUserId, 'user-B');
      await h.controller.confirmLog(data, imageFile: photo);
      await h.container
          .read(dailyStoryControllerProvider(FoodHarness.date).future);
      final writes = h.requests.where((o) => o.method == 'POST').length;
      await h.switchAccount('test-account-A');
      expect(h.container.read(profileProvider).confirmedUserId, 'user-A');
      final beforeRetry = h.requests.where((o) => o.method == 'POST').length;
      await expectLater(
          h.controller.confirmLog(data, imageFile: photo), throwsA(unknown));
      expect(h.requests.where((o) => o.method == 'POST').length, beforeRetry);
      expect(beforeRetry, writes + 1); // Only the real login POST.
    });

    test('$stage pending at logout cannot continue or unlock returning A',
        () async {
      final entered = Completer<void>();
      final response = Completer<ResponseBody>();
      late FoodHarness h;
      h = FoodHarness(onRequest: (o) async {
        if (o.method == 'POST' &&
            o.headers['Authorization'] == 'Bearer test-account-A' &&
            o.path.endsWith(stage == 'story' ? '/log-story' : '/logs')) {
          entered.complete();
          return response.future;
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      final photo = h.photo();
      final data = mealData();
      final pending = h.controller.confirmLog(data, imageFile: photo);
      final rejected = expectLater(pending, throwsA(isA<NutritionSessionChanged>()));
      await entered.future;
      await h.switchAccount('test-account-B');
      response.complete(foodReply(stage == 'story'
          ? {'log_id': 'late-story-A'}
          : {'status': 'saved'}));
      await rejected;
      expect(h.container.read(profileProvider).confirmedUserId, 'user-B');
      expect(h.writes('/logs'), stage == 'story' ? 0 : 1);
      await h.controller.confirmLog(data, imageFile: photo);
      await h.container
          .read(dailyStoryControllerProvider(FoodHarness.date).future);
      await h.switchAccount('test-account-A');
      final writes = h.requests.where((o) => o.method == 'POST').length;
      await expectLater(
          h.controller.confirmLog(data, imageFile: photo),
          throwsA(isA<ConfirmLogException>()
              .having((e) => e.outcomeUnknown, 'uncertain', true)));
      expect(h.requests.where((o) => o.method == 'POST').length, writes);
    });
  }

  test('missing identity blocks confirmation and photo-only writes', () async {
    final h = FoodHarness();
    await h.start();
    addTearDown(h.close);
    h.container.read(profileProvider.notifier).resetSession();
    final before = h.requests.where((o) => o.method == 'POST').length;
    await expectLater(h.controller.confirmLog(mealData(), imageFile: h.photo()),
        throwsA(isA<NutritionSessionChanged>()));
    await expectLater(
        h.controller.saveStoryWithoutAI(
            imageFile: h.photo(), mealType: 'lunch', note: 'Local test'),
        throwsA(isA<ConfirmLogException>()));
    expect(h.requests.where((o) => o.method == 'POST').length, before);
  });

  test('token refresh keeps the stable account uncertain lock', () async {
    late FoodHarness h;
    h = FoodHarness(onRequest: (o) async {
      if (o.method == 'POST' && o.path.endsWith('/log-story')) {
        throw DioException(
            requestOptions: o, type: DioExceptionType.receiveTimeout);
      }
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    final photo = h.photo();
    final data = mealData();
    final owner = await h.container.read(nutritionSessionProvider).capture();
    await expectLater(h.controller.confirmLog(data, imageFile: photo),
        throwsA(isA<ConfirmLogException>()));
    await const FlutterSecureStorage()
        .write(key: 'auth_token', value: 'refreshed-test-account-A');
    await expectLater(h.controller.confirmLog(data, imageFile: photo),
        throwsA(isA<ConfirmLogException>()));
    expect(h.writes('/log-story'), 1);
    await expectLater(owner.validate(), throwsA(isA<NutritionSessionChanged>()));
  });
}
