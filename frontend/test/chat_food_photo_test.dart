import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/models/ai_analysis_result.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_attachment_sheet.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_food_analysis_loading.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_food_failure.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_food_result.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_meal_estimate_card.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_user_photo_message.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _FakeFoodChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  final List<String> sentMessages = [];
  bool clearChatCalled = false;
  bool markMealLoggedCalled = false;

  _FakeFoodChatNotifier({ChatState? initialState})
      : super(initialState ?? ChatState(messages: []));

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> sendMessage(String text) async {
    sentMessages.add(text);
    state = state.copyWith(
      messages: [...state.messages, ChatMessage(role: 'user', content: text)],
      isLoading: false,
    );
  }

  @override
  void clearChat() {
    clearChatCalled = true;
    state = ChatState(messages: [], foodAnalysisState: null);
  }

  @override
  Future<void> retry() async {}

  @override
  void clearError() {
    state = state.copyWith(clearError: true, clearFailedUserMessage: true);
  }

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption}) async {
    state = state.copyWith(
      foodAnalysisState: ChatFoodAnalysisState(
        status: FoodAnalysisStatus.analyzing,
        imagePath: file.path,
        imageFile: file,
        userCaption: caption ?? 'Can I fit this into today?',
      ),
    );
  }

  @override
  void markMealLogged() {
    markMealLoggedCalled = true;
    if (state.foodAnalysisState != null) {
      state = state.copyWith(
        foodAnalysisState: state.foodAnalysisState!.copyWith(isMealLogged: true),
      );
    }
  }

  @override
  void clearFoodAnalysis() {
    state = state.copyWith(clearFoodAnalysis: true);
  }
}

Widget _buildTestWrapper({
  required _FakeFoodChatNotifier notifier,
}) {
  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith((ref) => notifier),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.dark(),
      home: const ChatScreen(),
    ),
  );
}

AIAnalysisResult _createSampleResult({
  String foodName = 'Grilled chicken & rice bowl',
  double calories = 620.0,
  double protein = 42.0,
  double carbs = 68.0,
  double fat = 18.0,
}) {
  return AIAnalysisResult(
    foodName: foodName,
    foodLabel: 'grilled_chicken_bowl',
    confidence: 0.94,
    lowConfidence: false,
    grams: 350.0,
    calories: calories,
    protein: protein,
    carbs: carbs,
    fat: fat,
    per100g: {'calories': 177, 'protein': 12, 'carbs': 19, 'fat': 5},
    nutritionSource: 'usda',
    top3: const [],
  );
}

void main() {
  group('Saman Chat Phase 5 — Food Photo Flow', () {
    testWidgets('1. Tapping [+] exposes Food photo action sheet',
        (tester) async {
      final fakeNotifier = _FakeFoodChatNotifier();
      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Find attachment button by semantic label
      final attachBtn = find.bySemanticsLabel('Add attachment');
      expect(attachBtn, findsOneWidget);

      await tester.tap(attachBtn);
      await tester.pumpAndSettle();

      // Verify attachment sheet options
      expect(find.byType(SamanAttachmentSheet), findsOneWidget);
      expect(find.text('Take food photo'), findsOneWidget);
      expect(find.text('Upload image'), findsOneWidget);
      expect(find.text('Add attachment'), findsOneWidget);
    });

    testWidgets('2. Photo message renders user photo card with caption',
        (tester) async {
      final fakeNotifier = _FakeFoodChatNotifier(
        initialState: ChatState(
          foodAnalysisState: const ChatFoodAnalysisState(
            status: FoodAnalysisStatus.analyzing,
            imagePath: 'https://example.com/meal.jpg',
            userCaption: 'Can I fit this into today?',
          ),
        ),
      );

      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(SamanUserPhotoMessage), findsOneWidget);
      expect(find.text('Can I fit this into today?'), findsOneWidget);
    });

    testWidgets('3 & 4. State 06 Loading renders status and no calories/macros',
        (tester) async {
      final fakeNotifier = _FakeFoodChatNotifier(
        initialState: ChatState(
          foodAnalysisState: const ChatFoodAnalysisState(
            status: FoodAnalysisStatus.analyzing,
            imagePath: 'https://example.com/meal.jpg',
            userCaption: 'Can I fit this into today?',
          ),
        ),
      );

      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(SamanFoodAnalysisLoading), findsOneWidget);
      expect(find.text('Looking at your meal...'), findsOneWidget);
      expect(
        find.text('Checking the portion and main ingredients...'),
        findsOneWidget,
      );

      // Composer should show looking at meal hint
      expect(find.text('Saman is looking at your meal...'), findsOneWidget);

      // NO calories or macros during loading
      expect(find.text('kcal'), findsNothing);
      expect(find.text('Protein'), findsNothing);
      expect(find.text('Carbs'), findsNothing);
      expect(find.text('Fat'), findsNothing);
    });

    testWidgets('5-8. State 03 Success renders meal estimate, macros & generic Log meal',
        (tester) async {
      final result = _createSampleResult();
      final fakeNotifier = _FakeFoodChatNotifier(
        initialState: ChatState(
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.success,
            imagePath: 'https://example.com/meal.jpg',
            userCaption: 'Can I fit this into today?',
            result: result,
          ),
        ),
      );

      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(find.byType(SamanFoodResult), findsOneWidget);
      expect(find.byType(SamanMealEstimateCard), findsOneWidget);

      // Meal name and calories
      expect(find.text('Grilled chicken & rice bowl'), findsOneWidget);
      expect(find.text('~620 kcal'), findsWidgets);

      // 3-column macros
      expect(find.text('PROTEIN'), findsOneWidget);
      expect(find.text('42g'), findsOneWidget);
      expect(find.text('CARBS'), findsOneWidget);
      expect(find.text('68g'), findsOneWidget);
      expect(find.text('FAT'), findsOneWidget);
      expect(find.text('18g'), findsOneWidget);

      // Generic Log meal action exists
      expect(find.text('Log meal'), findsOneWidget);

      // No hardcoded meal type
      expect(find.text('Log as lunch'), findsNothing);
      expect(find.text('Log dinner'), findsNothing);
      expect(find.text('Log breakfast'), findsNothing);
    });

    testWidgets('9-13. State 08 Failure preserves photo, shows guidance & actions',
        (tester) async {
      final fakeNotifier = _FakeFoodChatNotifier(
        initialState: ChatState(
          foodAnalysisState: const ChatFoodAnalysisState(
            status: FoodAnalysisStatus.failure,
            imagePath: 'https://example.com/meal.jpg',
            userCaption: 'Can I fit this into today?',
            errorMessage:
                "I couldn't estimate this meal confidently from the photo.",
          ),
        ),
      );

      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Photo is preserved
      expect(find.byType(SamanUserPhotoMessage), findsOneWidget);

      // Failure presentation
      expect(find.byType(SamanFoodFailure), findsOneWidget);
      expect(
        find.text("I couldn't estimate this meal confidently from the photo."),
        findsOneWidget,
      );

      // Guidance tips
      expect(find.text('Try taking another photo with:'), findsOneWidget);
      expect(find.text('the full plate visible'), findsOneWidget);
      expect(find.text('better lighting'), findsOneWidget);
      expect(find.text('a clearer top-down angle'), findsOneWidget);

      // Recovery actions
      expect(find.text('Retake photo'), findsOneWidget);
      expect(find.text('Enter meal manually'), findsOneWidget);

      // No fabricated macros
      expect(find.text('kcal'), findsNothing);
      expect(find.text('Protein'), findsNothing);
    });

    testWidgets('14. Text chat messages remain active alongside food photo',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeNotifier = _FakeFoodChatNotifier(
        initialState: ChatState(
          messages: [
            ChatMessage(
              role: 'user',
              content: 'Can you check my hydration today?',
            ),
            ChatMessage(
              role: 'assistant',
              content: 'You logged 1,500ml so far, 500ml left.',
            ),
          ],
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.success,
            imagePath: 'https://example.com/meal.jpg',
            result: _createSampleResult(),
          ),
        ),
      );

      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      // Both food photo card and text messages are visible
      expect(find.byType(SamanMealEstimateCard), findsOneWidget);
      expect(find.text('Can you check my hydration today?'), findsOneWidget);
      expect(
        find.text('You logged 1,500ml so far, 500ml left.'),
        findsOneWidget,
      );
    });

    testWidgets('17. 360px viewport has no overflow across all food photo states',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Test Success state on 360px
      final fakeNotifier = _FakeFoodChatNotifier(
        initialState: ChatState(
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.success,
            imagePath: 'https://example.com/meal.jpg',
            result: _createSampleResult(),
          ),
        ),
      );

      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SamanMealEstimateCard), findsOneWidget);
    });

    testWidgets('15. Meal logged state updates action button to "✓ Meal logged"',
        (tester) async {
      final fakeNotifier = _FakeFoodChatNotifier(
        initialState: ChatState(
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.success,
            imagePath: 'https://example.com/meal.jpg',
            result: _createSampleResult(),
            isMealLogged: true,
          ),
        ),
      );

      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(find.text('✓ Meal logged'), findsOneWidget);
      expect(find.text('Log meal'), findsNothing);
    });

    testWidgets('16. New chat / clearChat clears food analysis state',
        (tester) async {
      final fakeNotifier = _FakeFoodChatNotifier(
        initialState: ChatState(
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.success,
            imagePath: 'https://example.com/meal.jpg',
            result: _createSampleResult(),
          ),
        ),
      );

      await tester.pumpWidget(_buildTestWrapper(notifier: fakeNotifier));
      await tester.pumpAndSettle();

      expect(find.byType(SamanMealEstimateCard), findsOneWidget);

      // Trigger clear
      fakeNotifier.clearChat();
      await tester.pumpAndSettle();

      expect(find.byType(SamanMealEstimateCard), findsNothing);
      expect(fakeNotifier.clearChatCalled, isTrue);
    });
  });
}
