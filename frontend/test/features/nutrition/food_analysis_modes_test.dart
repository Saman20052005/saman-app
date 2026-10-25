import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/providers/daily_story_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/services/nutrition_service.dart';
import 'package:health_ai_app/utils/auth_helper.dart';
import 'daily_story_controller_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in <String?>[null, '', 'standard', ' Advanced ']) {
    test('active service forwards image and optional mode: $mode', () async {
      final h = FoodHarness();
      await h.start();
      addTearDown(h.close);
      final result =
          await NutritionService().analyzeFoodImage(h.photo(), mode: mode);
      expect(result!.nutritionSource, 'gemini_estimate');
      final request =
          h.requests.singleWhere((o) => o.path.endsWith('/analyze'));
      final form = request.data as FormData;
      expect(form.files.single.key, 'image');
      expect(
          Map.fromEntries(form.fields)['mode'],
          mode == null || mode.trim().isEmpty
              ? null
              : mode.trim().toLowerCase());
    });
  }

  for (final status in [401, 403, 422, 500]) {
    test(
        'service preserves typed HTTP $status error without raw payload feedback',
        () async {
      late FoodHarness h;
      h = FoodHarness(
          onRequest: (o) async => o.path.endsWith('/analyze')
              ? foodReply({'detail': 'SECRET server payload'}, status)
              : h.defaults(o));
      await h.start();
      addTearDown(h.close);
      await expectLater(
          NutritionService().analyzeFoodImage(h.photo()),
          throwsA(isA<DioException>()
              .having((e) => e.response?.statusCode, 'status', status)));
    });

    test(
        'Chat and Nutrition surface $status safely; only 401 enters auth recovery',
        () async {
      late FoodHarness h;
      h = FoodHarness(onRequest: (o) async {
        if (o.path.endsWith('/analyze'))
          return foodReply({'detail': 'SECRET'}, status);
        if (o.path.contains('/users/') || o.path.contains('/profile'))
          return foodReply({}, 401);
        return h.defaults(o);
      });
      await h.start();
      addTearDown(h.close);
      final chat = h.container.read(chatControllerProvider.notifier);
      await chat.analyzeFoodPhoto(h.photo(), mode: 'advanced');
      final state = h.container.read(chatControllerProvider).foodAnalysisState!;
      expect(state.status, FoodAnalysisStatus.failure);
      expect(state.errorMessage, isNot(contains('SECRET')));
      expect(state.mode, 'advanced');
      expect(state.imageFile, isNotNull);
      if (status == 403) expect(state.errorMessage, contains('Standard'));
      if (status == 422)
        expect(state.errorMessage, contains('check the photo'));
      await expectLater(h.controller.analyzeImage(h.photo(), mode: 'advanced'),
          throwsA(isA<DioException>()));
      expect(await AuthHelper.getToken(), 'test-account-A');
      expect(h.container.read(profileProvider).status,
          status == 401 ? ProfileStatus.unauthorized : ProfileStatus.initial);
      expect(h.writes('/log-story'), 0);
      expect(h.writes('/logs'), 0);
    });
  }
  test('incomplete successful response cannot become a zero-calorie estimate',
      () async {
    late FoodHarness h;
    h = FoodHarness(
        onRequest: (o) async => o.path.endsWith('/analyze')
            ? foodReply({'food_name': 'Unknown'})
            : h.defaults(o));
    await h.start();
    addTearDown(h.close);
    await expectLater(
        NutritionService().analyzeFoodImage(h.photo()), throwsFormatException);
    final chat = h.container.read(chatControllerProvider.notifier);
    await chat.analyzeFoodPhoto(h.photo());
    expect(h.container.read(chatControllerProvider).foodAnalysisState!.status,
        FoodAnalysisStatus.failure);
  });
}
