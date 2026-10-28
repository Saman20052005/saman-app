import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/providers/daily_story_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/nutrition/widgets/meal_review_dialog.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/screens/login/login_controller.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

// Shared isolated HTTP harness. Production controllers, service, repository and
// multipart datasource all execute; no request can reach an external service.
class FoodAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) respond;
  FoodAdapter(this.respond);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancelFuture) =>
      respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody foodReply(Object data, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

const foodPayload = {
  'food_name': 'Rice',
  'food_label': 'rice',
  'grams': 100,
  'nutrition': {'calories': 130, 'protein': 2.7, 'carbs': 28, 'fat': 0.3},
  'nutrition_source': 'gemini_estimate',
  'confidence': 0.9,
};

MealLogData mealData() => MealLogData(
    foodName: 'Rice',
    foodLabel: 'rice',
    mealType: 'lunch',
    grams: 100,
    calories: 130,
    protein: 2.7,
    carbs: 28,
    fat: 0.3,
    loggedAt: '2026-10-23T12:00:00');

class FoodHarness {
  static const date = '2026-10-23';
  final requests = <RequestOptions>[];
  final Future<ResponseBody> Function(RequestOptions)? onRequest;
  late ProviderContainer container;
  late HttpClientAdapter previousAdapter;
  late ProviderSubscription<AsyncValue<List<dynamic>>> subscription;
  FoodHarness({this.onRequest});

  Future<void> start() async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'test-account-A'});
    AuthHelper.resetStorageForTesting();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    previousAdapter = ApiClient.dio.httpClientAdapter;
    ApiClient.dio.httpClientAdapter = FoodAdapter((options) async {
      requests.add(options);
      if (options.path.endsWith('/api/user/profile') ||
          options.path.endsWith('/api/auth/login')) {
        return defaults(options);
      }
      if (onRequest != null) return onRequest!(options);
      return defaults(options);
    });
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await container.read(profileProvider.notifier).loadProfile();
    subscription =
        container.listen(dailyStoryControllerProvider(date), (_, __) {});
    await container.read(dailyStoryControllerProvider(date).future);
  }

  ResponseBody defaults(RequestOptions o) {
    if (o.path.endsWith('/api/auth/login')) {
      final account = (o.data as Map)['email'] == 'b@saman.test' ? 'B' : 'A';
      return foodReply({
        'access_token': 'test-account-$account',
        'user_info': {'email': '${account.toLowerCase()}@saman.test'},
      });
    }
    if (o.path.endsWith('/api/user/profile')) {
      final account = o.headers['Authorization'] == 'Bearer test-account-B'
          ? 'B'
          : 'A';
      return foodReply({'user_id': 'user-$account', 'profile': {}});
    }
    if (o.method == 'GET') return foodReply({'stories': []});
    if (o.path.endsWith('/analyze')) return foodReply(foodPayload);
    if (o.path.endsWith('/log-story')) return foodReply({'log_id': 'story-1'});
    return foodReply({'status': 'saved'});
  }

  DailyStoryController get controller =>
      container.read(dailyStoryControllerProvider(date).notifier);
  XFile photo() =>
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'meal.jpg');
  int writes(String suffix) => requests
      .where((o) => o.method == 'POST' && o.path.endsWith(suffix))
      .length;

  Future<void> switchAccount(String token) async {
    await AuthHelper.logout(container);
    final login = LoginController();
    try {
      await login.submitEmailAuth(
        isLoginMode: true,
        email: token == 'test-account-B' ? 'b@saman.test' : 'a@saman.test',
        password: 'synthetic-test-password',
      );
    } finally {
      login.dispose();
    }
    await container.read(profileProvider.notifier).loadProfile();
    await container.read(dailyStoryControllerProvider(date).future);
  }

  void close() {
    subscription.close();
    container.dispose();
    ApiClient.dio.httpClientAdapter = previousAdapter;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('analysis performs no persistence; confirmation preserves file contract',
      () async {
    final h = FoodHarness();
    await h.start();
    addTearDown(h.close);
    final photo = h.photo();
    await h.controller.analyzeImage(photo, mode: 'advanced');
    expect(h.writes('/log-story'), 0);
    expect(h.writes('/logs'), 0);
    await h.controller.confirmLog(mealData(), imageFile: photo);
    expect(h.writes('/log-story'), 1);
    expect(h.writes('/logs'), 1);
    final form = h.requests
        .firstWhere((o) => o.method == 'POST' && o.path.endsWith('/log-story'))
        .data as FormData;
    expect(form.files.single.key, 'file');
    expect(Map.fromEntries(form.fields)['calories'], '130.0');
  });

  test('concurrent confirmation is rejected before a second write', () async {
    final entered = Completer<void>();
    final story = Completer<ResponseBody>();
    late FoodHarness h;
    h = FoodHarness(onRequest: (o) async {
      if (o.method == 'POST' && o.path.endsWith('/log-story')) {
        entered.complete();
        return story.future;
      }
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    final data = mealData();
    final first = h.controller.confirmLog(data);
    await entered.future;
    await expectLater(
        h.controller.confirmLog(data),
        throwsA(isA<ConfirmLogException>()
            .having((e) => e.stage, 'stage', ConfirmLogFailureStage.busy)));
    story.complete(foodReply({'log_id': 'story-1'}));
    await first;
    expect(h.writes('/log-story'), 1);
    expect(h.writes('/logs'), 1);
  });

  test(
      'partial failure throws; retry reuses confirmed Story and original input',
      () async {
    var fail = true;
    late FoodHarness h;
    h = FoodHarness(onRequest: (o) async {
      if (o.method == 'POST' && o.path.endsWith('/logs') && fail) {
        return foodReply({'detail': 'rejected'}, 422);
      }
      return h.defaults(o);
    });
    await h.start();
    addTearDown(h.close);
    final data = mealData();
    final photo = h.photo();
    await expectLater(
        h.controller.confirmLog(data, imageFile: photo),
        throwsA(isA<ConfirmLogException>()
            .having((e) => e.storySaved, 'story saved', true)
            .having((e) => e.canRetry, 'retry', true)));
    fail = false;
    await h.controller.confirmLog(data, imageFile: photo);
    expect(h.writes('/log-story'), 1);
    expect(h.writes('/logs'), 2);
    // Completed operation also survives provider invalidation after success.
    await h.container
        .read(dailyStoryControllerProvider(FoodHarness.date).future);
    await h.controller.confirmLog(data, imageFile: photo);
    expect(h.writes('/logs'), 2);
  });

  for (final stage in ['story', 'meal']) {
    test('$stage receive timeout blocks blind retry', () async {
      late FoodHarness h;
      h = FoodHarness(onRequest: (o) async {
        if (o.method == 'POST' &&
            o.path.endsWith(stage == 'story' ? '/log-story' : '/logs')) {
          throw DioException(
              requestOptions: o, type: DioExceptionType.receiveTimeout);
        }
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      final data = mealData();
      final photo = h.photo();
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
            h.controller.confirmLog(data, imageFile: photo),
            throwsA(isA<ConfirmLogException>()
                .having((e) => e.outcomeUnknown, 'unknown', true)
                .having((e) => e.canRetry, 'retry', false)));
      }
      expect(h.writes('/log-story'), 1);
      expect(h.writes('/logs'), stage == 'story' ? 0 : 1);
    });
  }

  test('photo-only is blocked without any write request', () async {
    final h = FoodHarness();
    await h.start();
    addTearDown(h.close);
    await expectLater(
        h.controller.saveStoryWithoutAI(
            imageFile: h.photo(), mealType: 'lunch', note: 'Keep my note'),
        throwsA(isA<ConfirmLogException>().having(
            (e) => e.stage, 'stage', ConfirmLogFailureStage.photoOnly)));
    expect(h.requests.where((o) => o.method == 'POST'), isEmpty);
  });
}
