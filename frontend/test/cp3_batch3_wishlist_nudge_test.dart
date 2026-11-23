import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/shop/data/repositories/shared_preferences_shop_wishlist_repository.dart';
import 'package:health_ai_app/models/saman_nudge.dart';
import 'package:health_ai_app/services/api_client.dart';

/// Mock HTTP adapter to capture and respond to Dio network calls in tests.
class _MockHttpClientAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  _MockHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 1: SharedPreferencesShopWishlistRepository', () {
    test('Constructor with single arg (prefs) functions properly for local operations', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesShopWishlistRepository.storageKey: ['prod_1'],
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPreferencesShopWishlistRepository(prefs);
      addTearDown(repo.dispose);

      // Verify initial read
      var savedIds = await repo.getSavedProductIds();
      expect(savedIds, ['prod_1']);
      expect(await repo.isSaved('prod_1'), isTrue);
      expect(await repo.isSaved('prod_2'), isFalse);

      // save: newest at index 0
      await repo.save('prod_2');
      savedIds = await repo.getSavedProductIds();
      expect(savedIds, ['prod_2', 'prod_1']);

      // toggle existing: removes
      final wasSavedAfterToggle1 = await repo.toggle('prod_1');
      expect(wasSavedAfterToggle1, isFalse);
      savedIds = await repo.getSavedProductIds();
      expect(savedIds, ['prod_2']);

      // toggle non-existing: inserts at 0
      final wasSavedAfterToggle2 = await repo.toggle('prod_3');
      expect(wasSavedAfterToggle2, isTrue);
      savedIds = await repo.getSavedProductIds();
      expect(savedIds, ['prod_3', 'prod_2']);

      // remove
      await repo.remove('prod_2');
      savedIds = await repo.getSavedProductIds();
      expect(savedIds, ['prod_3']);
    });

    test('syncEnabled: true - syncFromRemote merges local + remote, updates prefs and emits stream', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesShopWishlistRepository.storageKey: ['local_new', 'shared_id'],
      });
      final prefs = await SharedPreferences.getInstance();

      final capturedCalls = <String>[];
      Map<String, dynamic>? lastPutBody;

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
      dio.httpClientAdapter = _MockHttpClientAdapter((options) {
        capturedCalls.add('${options.method} ${options.uri.path}');
        if (options.method == 'GET' && options.uri.path.endsWith('/api/shop/wishlist')) {
          return ResponseBody.fromString(
            jsonEncode({
              'saved_product_ids': ['shared_id', 'remote_only_1', 'remote_only_2'],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (options.method == 'PUT' && options.uri.path.endsWith('/api/shop/wishlist')) {
          if (options.data is Map) {
            lastPutBody = Map<String, dynamic>.from(options.data as Map);
          }
          return ResponseBody.fromString(
            jsonEncode({'saved_product_ids': options.data['saved_product_ids']}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{"detail":"not found"}', 404);
      });

      final repo = SharedPreferencesShopWishlistRepository(
        prefs,
        dio: dio,
        baseUrl: 'https://example.com',
        syncEnabled: true,
      );
      addTearDown(repo.dispose);

      final streamEmissions = <List<String>>[];
      final sub = repo.watchSavedProductIds().listen(streamEmissions.add);
      addTearDown(sub.cancel);

      await repo.syncFromRemote();

      // Expected merged: local preserved first in order, remote not in local appended
      final expectedMerged = ['local_new', 'shared_id', 'remote_only_1', 'remote_only_2'];
      expect(await repo.getSavedProductIds(), expectedMerged);
      expect(prefs.getStringList(SharedPreferencesShopWishlistRepository.storageKey), expectedMerged);
      expect(streamEmissions, isNotEmpty);
      expect(streamEmissions.last, expectedMerged);

      // Because merged != remote, it should have pushed the merged list to remote
      expect(capturedCalls, contains('PUT /api/shop/wishlist'));
      expect(lastPutBody?['saved_product_ids'], expectedMerged);
    });

    test('syncEnabled: true - toggle and save update local immediately and invoke PUT /api/shop/wishlist', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesShopWishlistRepository.storageKey: ['prod_1'],
      });
      final prefs = await SharedPreferences.getInstance();

      final putPayloads = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
      dio.httpClientAdapter = _MockHttpClientAdapter((options) {
        if (options.method == 'PUT' && options.uri.path.endsWith('/api/shop/wishlist')) {
          if (options.data is Map) {
            putPayloads.add(Map<String, dynamic>.from(options.data as Map));
          }
          return ResponseBody.fromString(
            jsonEncode({'saved_product_ids': options.data['saved_product_ids']}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{"detail":"not found"}', 404);
      });

      final repo = SharedPreferencesShopWishlistRepository(
        prefs,
        dio: dio,
        baseUrl: 'https://example.com',
        syncEnabled: true,
      );
      addTearDown(repo.dispose);

      // save() adds immediately
      await repo.save('prod_2');
      expect(await repo.getSavedProductIds(), ['prod_2', 'prod_1']);

      // Allow unawaited remote push to trigger
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(putPayloads, isNotEmpty);
      expect(putPayloads.last['saved_product_ids'], ['prod_2', 'prod_1']);

      // toggle() updates immediately
      final toggledResult = await repo.toggle('prod_1');
      expect(toggledResult, isFalse);
      expect(await repo.getSavedProductIds(), ['prod_2']);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(putPayloads.last['saved_product_ids'], ['prod_2']);
    });

    test('syncEnabled: true - fail-soft on network errors (500 / connection error)', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesShopWishlistRepository.storageKey: ['prod_base'],
      });
      final prefs = await SharedPreferences.getInstance();

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
      dio.httpClientAdapter = _MockHttpClientAdapter((options) {
        if (options.method == 'GET') {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: 500,
              statusMessage: 'Internal Server Error',
            ),
          );
        }
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Network unreachable',
        );
      });

      final repo = SharedPreferencesShopWishlistRepository(
        prefs,
        dio: dio,
        baseUrl: 'https://example.com',
        syncEnabled: true,
      );
      addTearDown(repo.dispose);

      // syncFromRemote should fail-soft without throwing
      await expectLater(repo.syncFromRemote(), completes);
      expect(await repo.getSavedProductIds(), ['prod_base']);

      // save should succeed locally despite remote PUT network failure
      await expectLater(repo.save('prod_offline'), completes);
      expect(await repo.getSavedProductIds(), ['prod_offline', 'prod_base']);

      // toggle should succeed locally despite remote PUT network failure
      final toggleRes = await repo.toggle('prod_base');
      expect(toggleRes, isFalse);
      expect(await repo.getSavedProductIds(), ['prod_offline']);
    });
  });

  group('Part 2: SamanNudge & SamanNudgeHelper', () {
    test('SamanNudge.fromJson parses snake_case fields correctly and preserves defaults', () {
      final json = {
        'id': 'nudge_custom_1',
        'message': 'Đã đến giờ nạp protein',
        'supporting_line': 'Còn thiếu 40g protein',
        'primary_label': 'Xem thực đơn',
        'secondary_label': 'Nhắc lại sau',
        'prompt_to_send': 'Gợi ý bữa phụ giàu protein',
      };

      final nudge = SamanNudge.fromJson(json);
      expect(nudge.id, 'nudge_custom_1');
      expect(nudge.message, 'Đã đến giờ nạp protein');
      expect(nudge.supportingLine, 'Còn thiếu 40g protein');
      expect(nudge.primaryLabel, 'Xem thực đơn');
      expect(nudge.secondaryLabel, 'Nhắc lại sau');
      expect(nudge.promptToSend, 'Gợi ý bữa phụ giàu protein');
      expect(nudge.timestamp, isNotNull);

      // Default fallbacks when optional snake_case fields are omitted
      final defaultNudge = SamanNudge.fromJson(const {'message': 'Thông điệp mặc định'});
      expect(defaultNudge.id, 'ai_nudge');
      expect(defaultNudge.message, 'Thông điệp mặc định');
      expect(defaultNudge.supportingLine, isNull);
      expect(defaultNudge.primaryLabel, 'Ask Saman');
      expect(defaultNudge.secondaryLabel, 'Later');
      expect(defaultNudge.promptToSend, isNull);
    });

    test('SamanNudgeHelper.fromDailyBrief prioritizes nudge, falls back to brief, returns null if empty', () {
      // 1. Prioritizes 'nudge' object when present
      final payloadWithNudge = {
        'nudge': {
          'id': 'priority_nudge',
          'message': 'Ưu tiên thông điệp nudge',
          'prompt_to_send': 'Prompt từ nudge',
        },
        'daily_brief': 'Tóm tắt brief bị bỏ qua',
      };
      final parsedNudge = SamanNudgeHelper.fromDailyBrief(payloadWithNudge);
      expect(parsedNudge, isNotNull);
      expect(parsedNudge!.id, 'priority_nudge');
      expect(parsedNudge.message, 'Ưu tiên thông điệp nudge');
      expect(parsedNudge.promptToSend, 'Prompt từ nudge');

      // 2. Falls back to 'daily_brief' or 'brief' when nudge is absent or message is empty
      final payloadWithBrief = {
        'daily_brief': 'Hôm nay bạn đã hoàn thành 80% chỉ tiêu.',
      };
      final fallbackNudge = SamanNudgeHelper.fromDailyBrief(payloadWithBrief);
      expect(fallbackNudge, isNotNull);
      expect(fallbackNudge!.id, 'daily_brief_nudge');
      expect(fallbackNudge.message, 'Hôm nay bạn đã hoàn thành 80% chỉ tiêu.');
      expect(fallbackNudge.primaryLabel, 'Hỏi Saman');
      expect(fallbackNudge.secondaryLabel, 'Để sau');
      expect(fallbackNudge.promptToSend, 'Dựa trên tình hình hôm nay, tôi nên làm gì tiếp theo?');

      // 3. Fallback with key 'brief'
      final payloadWithShortKeyBrief = {
        'brief': 'Brief ngắn hạn hôm nay.',
      };
      final fallbackShortKey = SamanNudgeHelper.fromDailyBrief(payloadWithShortKeyBrief);
      expect(fallbackShortKey, isNotNull);
      expect(fallbackShortKey!.message, 'Brief ngắn hạn hôm nay.');

      // 4. Returns null when both nudge and brief are empty or missing
      expect(SamanNudgeHelper.fromDailyBrief({}), isNull);
      expect(SamanNudgeHelper.fromDailyBrief({'daily_brief': '   '}), isNull);
      expect(SamanNudgeHelper.fromDailyBrief({'nudge': {'message': '   '}}), isNull);
    });

    test('SamanNudgeHelper.buildGroundedHomeNudge returns null when no real data & no journey task, and returns grounded nudge on real deficit', () {
      // 1. Returns null when !hasRealNutritionData && pendingJourneyTaskTitle == null
      final ungroundedNudge = SamanNudgeHelper.buildGroundedHomeNudge(
        consumedCalories: 1000,
        targetCalories: 2000,
        consumedProtein: 40.0,
        targetProtein: 120.0,
        waterMl: 500,
        waterTargetMl: 2500,
        hasRealNutritionData: false,
        pendingJourneyTaskTitle: null,
      );
      expect(ungroundedNudge, isNull);

      // 2. Returns journey task nudge when pendingJourneyTaskTitle is provided
      final journeyNudge = SamanNudgeHelper.buildGroundedHomeNudge(
        consumedCalories: 0,
        targetCalories: 0,
        consumedProtein: 0,
        targetProtein: 0,
        waterMl: 0,
        waterTargetMl: 0,
        hasRealNutritionData: false,
        pendingJourneyTaskTitle: 'Chạy bộ 3km công viên',
      );
      expect(journeyNudge, isNotNull);
      expect(journeyNudge!.id, 'journey_task_nudge');
      expect(journeyNudge.message, contains('Chạy bộ 3km công viên'));
      expect(journeyNudge.promptToSend, contains('Chạy bộ 3km công viên'));

      // 3. Returns grounded protein deficit nudge with real numbers when hasRealNutritionData: true
      final proteinDeficitNudge = SamanNudgeHelper.buildGroundedHomeNudge(
        consumedCalories: 1500,
        targetCalories: 2200,
        consumedProtein: 60.0,
        targetProtein: 130.0, // 60 < 130 * 0.7 (= 91)
        waterMl: 2000,
        waterTargetMl: 2000,
        hasRealNutritionData: true,
        pendingJourneyTaskTitle: null,
      );
      expect(proteinDeficitNudge, isNotNull);
      expect(proteinDeficitNudge!.id, 'nutrition_deficit_nudge');
      expect(proteinDeficitNudge.message, contains('70g đạm'));
      expect(proteinDeficitNudge.message, contains('700 kcal'));
      expect(proteinDeficitNudge.supportingLine, contains('60 / 130g đạm'));

      // 4. Returns water deficit nudge when protein target is met but water is below 50%
      final waterDeficitNudge = SamanNudgeHelper.buildGroundedHomeNudge(
        consumedCalories: 2100,
        targetCalories: 2200,
        consumedProtein: 125.0,
        targetProtein: 130.0, // >= 130 * 0.7
        waterMl: 800,
        waterTargetMl: 2000, // 800 < 2000 * 0.5 (= 1000)
        hasRealNutritionData: true,
        pendingJourneyTaskTitle: null,
      );
      expect(waterDeficitNudge, isNotNull);
      expect(waterDeficitNudge!.id, 'water_hydration_nudge');
      expect(waterDeficitNudge.message, contains('800 ml'));
      expect(waterDeficitNudge.message, contains('1200 ml'));

      // 5. Returns null when hasRealNutritionData: true and all targets are well satisfied
      final allTargetsMetNudge = SamanNudgeHelper.buildGroundedHomeNudge(
        consumedCalories: 2200,
        targetCalories: 2200,
        consumedProtein: 130.0,
        targetProtein: 130.0,
        waterMl: 2000,
        waterTargetMl: 2000,
        hasRealNutritionData: true,
        pendingJourneyTaskTitle: null,
      );
      expect(allTargetsMetNudge, isNull);
    });
  });

  group('Part 3: ChatController.loadDailyBrief', () {
    test('Mock ApiClient.dio returns /api/chat/daily-brief with nudge -> state.dailyNudge updated correctly', () async {
      final originalAdapter = ApiClient.dio.httpClientAdapter;
      addTearDown(() {
        ApiClient.dio.httpClientAdapter = originalAdapter;
      });

      ApiClient.dio.httpClientAdapter = _MockHttpClientAdapter((options) {
        if (options.uri.path.endsWith('/api/chat/daily-brief')) {
          return ResponseBody.fromString(
            jsonEncode({
              'nudge': {
                'id': 'daily_coach_nudge_42',
                'message': 'Uống thêm 500ml nước trước giờ ngủ nhé!',
                'supporting_line': '• 1,500 / 2,000 ml nước đã uống',
                'primary_label': 'Ghi nhận nước',
                'secondary_label': 'Để sau',
                'prompt_to_send': 'Tôi vừa uống thêm 500ml nước, ghi nhận giúp tôi.',
              },
              'daily_brief': 'Hôm nay bạn đã hoàn thành buổi tập lưng xô xuất sắc!',
              'daily_brief_metrics': {
                'calories': 1800,
                'target_calories': 2200,
              },
              'dynamic_chips': [
                {'label': 'Xem nhật ký nước', 'prompt': 'Mở nhật ký nước hôm nay'}
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{"detail":"not found"}', 404);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);

      // Pre-check: initial dailyNudge should be null
      expect(container.read(chatControllerProvider).dailyNudge, isNull);

      await controller.loadDailyBrief();

      final state = container.read(chatControllerProvider);
      expect(state.dailyNudge, isNotNull);
      expect(state.dailyNudge!.id, 'daily_coach_nudge_42');
      expect(state.dailyNudge!.message, 'Uống thêm 500ml nước trước giờ ngủ nhé!');
      expect(state.dailyNudge!.promptToSend, 'Tôi vừa uống thêm 500ml nước, ghi nhận giúp tôi.');
      expect(state.dailyNudge!.supportingLine, '• 1,500 / 2,000 ml nước đã uống');
      expect(state.dailyNudge!.primaryLabel, 'Ghi nhận nước');
      expect(state.dailyNudge!.secondaryLabel, 'Để sau');
      expect(state.dailyBrief, 'Hôm nay bạn đã hoàn thành buổi tập lưng xô xuất sắc!');
      expect(state.dynamicChips, hasLength(1));
      expect(state.dynamicChips.first['label'], 'Xem nhật ký nước');
    });
  });
}
