import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/load_daily_plan_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_logged_meal_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_meal_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/update_water_usecase.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/models/saman_nudge.dart';
import 'package:health_ai_app/presentation/providers/active_workout_providers.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/widgets.dart';
import 'package:health_ai_app/screens/home_screen.dart';
import 'package:health_ai_app/services/api_client.dart';

class _MockAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  _MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

class _MockNutritionRepo extends Mock implements INutritionRepository {}

class _FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _FakeNutritionNotifier(NutritionPlan? plan) : super(AsyncValue.data(plan));

  int refreshCalls = 0;

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2000,
        protein: 140,
        carbs: 220,
        fat: 60,
      );

  @override
  Future<void> refreshCurrentPlan({
    String? dateStr,
    bool forceRefresh = true,
  }) async {
    refreshCalls++;
  }

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyChatController extends ChatController {
  _SpyChatController(super.ref, {ChatState? initial}) {
    if (initial != null) {
      state = initial;
    }
  }

  int loadDailyBriefCalls = 0;
  final List<bool> forceFlags = [];

  @override
  Future<void> loadDailyBrief({bool force = false}) async {
    loadDailyBriefCalls++;
    forceFlags.add(force);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('Wave 2 T-CONV.1 Convergence Unit Tests', () {
    test('ChatController.loadDailyBrief deduplicates non-forced and drops stale response on force=true or auth switch',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final originalAdapter = ApiClient.dio.httpClientAdapter;
      addTearDown(() => ApiClient.dio.httpClientAdapter = originalAdapter);

      var requestCount = 0;
      final firstEntered = Completer<void>();
      final secondEntered = Completer<void>();
      final firstCompleter = Completer<ResponseBody>();
      final secondCompleter = Completer<ResponseBody>();

      ApiClient.dio.httpClientAdapter = _MockAdapter((options) {
        if (options.uri.path.endsWith('/api/chat/daily-brief')) {
          requestCount++;
          if (requestCount == 1) {
            if (!firstEntered.isCompleted) firstEntered.complete();
            return firstCompleter.future;
          }
          if (requestCount == 2) {
            if (!secondEntered.isCompleted) secondEntered.complete();
            return secondCompleter.future;
          }
        }
        return ResponseBody.fromString('{}', 404);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(chatControllerProvider.notifier);

      // Concurrent non-forced calls collapse into 1 HTTP request
      final f1 = controller.loadDailyBrief();
      final f2 = controller.loadDailyBrief();
      await firstEntered.future;
      expect(requestCount, 1);

      // Force call triggers new request while first is still in flight
      final f3 = controller.loadDailyBrief(force: true);
      await secondEntered.future;
      expect(requestCount, 2);

      // Newer response arrives first
      secondCompleter.complete(ResponseBody.fromString(
        jsonEncode({
          'daily_brief': 'Fresh brief',
          'metrics': {'calories': 900, 'water_ml': 1000},
          'nudge': {'id': 'fresh', 'message': 'Fresh nudge'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ));
      await f3;
      expect(container.read(chatControllerProvider).dailyBrief, 'Fresh brief');
      expect(container.read(chatControllerProvider).dailyNudge?.message, 'Fresh nudge');

      // Stale first response resolves later -> must be ignored
      firstCompleter.complete(ResponseBody.fromString(
        jsonEncode({
          'daily_brief': 'Stale brief',
          'metrics': {'calories': 0, 'water_ml': 0},
          'nudge': {'id': 'stale', 'message': 'Stale nudge'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ));
      await Future.wait([f1, f2]);
      expect(container.read(chatControllerProvider).dailyBrief, 'Fresh brief');
      expect(container.read(chatControllerProvider).dailyNudge?.message, 'Fresh nudge');

      // Auth scope switch invalidates in-flight loadDailyBrief
      final thirdCompleter = Completer<ResponseBody>();
      ApiClient.dio.httpClientAdapter = _MockAdapter((options) => thirdCompleter.future);
      final f4 = controller.loadDailyBrief(force: true);
      container.read(workoutAuthScopeProvider.notifier).state++;
      thirdCompleter.complete(ResponseBody.fromString(
        jsonEncode({'daily_brief': 'Wrong account brief'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ));
      await f4;
      expect(container.read(chatControllerProvider).dailyBrief, isNull);
    });

    test('ActiveSessionSaver syncs nutritionProvider.refreshCurrentPlan and chatController.loadDailyBrief(force: true) on 201 and 409 match',
        () async {
      for (final isConflictMatch in [false, true]) {
        final dio = Dio();
        String? clientId;
        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            if (!isConflictMatch && options.method == 'POST') {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 201,
                data: {
                  'session_id': 'srv_id_1',
                  'session': {
                    'id': 'srv_id_1',
                    'planName': 'Upper',
                    'startedAt': '2026-11-18T02:00:00.000Z',
                    'finishedAt': '2026-11-18T02:20:00.000Z',
                    'exerciseLogs': [
                      {
                        'exerciseId': 'ex_1',
                        'exerciseSlug': 'ex_1',
                        'setNumber': 1,
                        'repsCompleted': 8,
                        'unit': 'reps',
                        'weightKg': 26.0,
                        'isCompleted': true,
                      }
                    ],
                    'totalDurationMinutes': 0,
                    'totalVolumeKg': 208,
                  },
                },
              ));
            }
            if (isConflictMatch && options.method == 'POST') {
              return handler.reject(DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 409),
                type: DioExceptionType.badResponse,
              ));
            }
            if (isConflictMatch && options.method == 'GET' && options.path.contains(clientId!)) {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'session': {
                    'id': 'srv_409_match',
                    'planName': 'Upper',
                    'startedAt': '2026-11-18T02:00:00.000Z',
                    'finishedAt': '2026-11-18T02:20:00.000Z',
                    'exerciseLogs': [
                      {
                        'exerciseId': 'ex_1',
                        'exerciseSlug': 'ex_1',
                        'setNumber': 1,
                        'repsCompleted': 8,
                        'unit': 'reps',
                        'weightKg': 26.0,
                        'isCompleted': true,
                      }
                    ],
                    'totalDurationMinutes': 0,
                    'totalVolumeKg': 208,
                  },
                },
              ));
            }
            return handler.next(options);
          },
        ));

        late _FakeNutritionNotifier fakeNutrition;
        late _SpyChatController spyChat;
        final container = ProviderContainer(
          overrides: [
            dioProvider.overrideWithValue(dio),
            nutritionProvider.overrideWith((ref) {
              fakeNutrition = _FakeNutritionNotifier(null);
              return fakeNutrition;
            }),
            chatControllerProvider.overrideWith((ref) {
              spyChat = _SpyChatController(ref);
              return spyChat;
            }),
          ],
        );
        addTearDown(container.dispose);

        final activeNotifier = container.read(activeWorkoutSessionProvider.notifier);
        clientId = activeNotifier.sessionId;
        activeNotifier.logActiveSet();

        final ok = await container.read(activeSessionSaverProvider.notifier).saveCurrentSession();
        expect(ok, isTrue);
        expect(fakeNutrition.refreshCalls, 1);
        expect(spyChat.loadDailyBriefCalls, 1);
        expect(spyChat.forceFlags, [true]);
      }
    });

    test('NutritionNotifier mutations refresh DailyBrief while loadDailyPlan does not', () async {
      final repo = _MockNutritionRepo();
      final plan = NutritionPlan(
        date: '2026-11-18',
        meals: [
          Meal(
            foodId: '1',
            name: 'Lunch',
            calories: 500,
            protein: 30,
            carbs: 50,
            fat: 15,
            weightGrams: 200,
            mealType: 'lunch',
            time: '12:00',
          ),
        ],
        currentWater: 500,
        targetWater: 2000,
        totalCaloriesConsumed: 500,
      );
      when(() => repo.getDailyPlan('2026-11-18', session: any(named: 'session')))
          .thenAnswer((_) async => plan);
      when(() => repo.addMeal(any())).thenAnswer((_) async => true);
      when(() => repo.quickRelogMeal(
            sourceLogId: any(named: 'sourceLogId'),
            mealType: any(named: 'mealType'),
            date: any(named: 'date'),
          )).thenAnswer((_) async => true);
      when(() => repo.updateWater(
            '2026-11-18',
            any(),
            deltaMl: any(named: 'deltaMl'),
            version: any(named: 'version'),
            idempotencyKey: any(named: 'idempotencyKey'),
            session: any(named: 'session'),
          )).thenAnswer((_) async => true);

      late _SpyChatController spyChat;
      final container = ProviderContainer(
        overrides: [
          chatControllerProvider.overrideWith((ref) {
            spyChat = _SpyChatController(ref);
            return spyChat;
          }),
          nutritionProvider.overrideWith((ref) => NutritionNotifier(
                ref: ref,
                repository: repo,
                loadDailyPlanUseCase: LoadDailyPlanUseCase(repo),
                updateWaterUseCase: UpdateWaterUseCase(repo),
                swapMealUseCase: SwapMealUseCase(repo),
                swapLoggedMealUseCase: SwapLoggedMealUseCase(repo),
              )),
        ],
      );
      addTearDown(container.dispose);

      // Initialize spyChat via read
      container.read(chatControllerProvider);
      final notifier = container.read(nutritionProvider.notifier);

      await notifier.loadDailyPlan(DateTime(2026, 11, 18), forceRefresh: true);
      expect(spyChat.loadDailyBriefCalls, 0);

      await notifier.addMeal(
        date: DateTime(2026, 11, 18),
        mealType: 'breakfast',
        foodId: 'oats',
        name: 'Oats',
        calories: 350,
        protein: 15,
        carbs: 50,
        fat: 8,
        weightGrams: 100,
      );
      expect(spyChat.loadDailyBriefCalls, 1);

      await notifier.quickRelogMeal(
        sourceLogId: 'src_1',
        date: DateTime(2026, 11, 18),
      );
      expect(spyChat.loadDailyBriefCalls, 2);

      await notifier.addWater(250, date: '2026-11-18');
      expect(spyChat.loadDailyBriefCalls, 3);

      await notifier.updateWater(1000, date: '2026-11-18');
      expect(spyChat.loadDailyBriefCalls, 4);
      expect(spyChat.forceFlags, [true, true, true, true]);
    });

    testWidgets('HomeScreen prioritizes plan.dynamicTarget and recomputes live activeNudge when dailyBriefMetrics is stale',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'user_fullname': 'Tester',
        'user_email': 'tester@saman.app',
      });
      final prefs = await SharedPreferences.getInstance();

      final plan = NutritionPlan(
        date: '2026-11-18',
        meals: [],
        currentWater: 2500,
        targetWater: 2500,
        totalCaloriesConsumed: 1950,
        totalProteinConsumed: 150,
        totalCarbsConsumed: 220,
        totalFatConsumed: 60,
        dayMode: 'training',
        dynamicTarget: const DynamicNutritionTarget(
          calories: 2350,
          protein: 170,
          carbs: 280,
          fat: 70,
          calorieDelta: 350,
          baseCalories: 2000,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier(plan)),
            macroTargetsProvider.overrideWithValue(
              const MacroTargets(calories: 2000, protein: 140, carbs: 220, fat: 60),
            ),
            chatControllerProvider.overrideWith(
              (ref) => _SpyChatController(
                ref,
                initial: ChatState(
                  dailyNudge: const SamanNudge(
                    id: 'stale',
                    message: 'Bạn chưa nạp đủ calo (0 kcal)',
                  ),
                  dailyBriefMetrics: const {
                    'calories': 0,
                    'water_ml': 0,
                  },
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final targetsCard = tester.widget<DailyTargetsCard>(find.byType(DailyTargetsCard));
      expect(targetsCard.caloriesConsumed, 1950);
      expect(targetsCard.caloriesTarget, 2350);
      expect(targetsCard.proteinTarget, 170.0);
      expect(targetsCard.carbsTarget, 280.0);
      expect(targetsCard.fatTarget, 70.0);

      final bar = tester.widget<SamanCompanionBar>(find.byType(SamanCompanionBar));
      expect(bar.message, isNotNull);
      expect(bar.message, contains('1950/2350 kcal'));
      expect(bar.message, contains('2500 ml nước'));
      expect(bar.message, isNot(contains('(0 kcal)')));
    });
  });
}
