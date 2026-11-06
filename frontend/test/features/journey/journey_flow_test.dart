import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:health_ai_app/features/journey/domain/models/journey_models.dart';
import 'package:health_ai_app/features/journey/data/repositories/fake_journey_repository.dart';
import 'package:health_ai_app/features/journey/presentation/providers/journey_providers.dart';
import 'package:health_ai_app/features/journey/presentation/screens/create_journey_screen.dart';
import 'package:health_ai_app/features/journey/presentation/screens/my_journey_screen.dart';
import 'package:health_ai_app/features/journey/presentation/screens/wallet_rewards_screen.dart';
import 'package:health_ai_app/features/journey/presentation/widgets/saman_journey_card.dart';

void main() {
  group('Journey Domain & Controller Flow Tests', () {
    late FakeJourneyRepository fakeRepo;
    late ProviderContainer container;

    setUp(() {
      fakeRepo = FakeJourneyRepository();
      container = ProviderContainer(
        overrides: [
          journeyRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial journey state is null when no active journey exists', () async {
      await container.read(journeyControllerProvider.notifier).loadActiveJourney();
      final state = container.read(journeyControllerProvider);
      expect(state.journey, isNull);
      expect(state.hasActiveJourney, isFalse);
    });

    test('Creating a journey initializes tasks, duration, and streak starts at 0', () async {
      final success = await container.read(journeyControllerProvider.notifier).createJourney(
            focus: JourneyFocus.hybrid,
            totalDays: 21,
            reminderTime: '20:00',
          );
      expect(success, isTrue);

      final currentJourney = container.read(journeyControllerProvider).journey;
      expect(currentJourney, isNotNull);
      expect(currentJourney!.focus, JourneyFocus.hybrid);
      expect(currentJourney.totalDays, 21);
      expect(currentJourney.reminderTime, '20:00');
      expect(currentJourney.status, JourneyStatus.active);
      expect(currentJourney.currentStreak, 0, reason: 'Streak must start at 0');
      expect(currentJourney.completedDaysCount, 0);
      expect(currentJourney.todayRecord, isNotNull);
    });

    test('Completing task marks it done, does NOT auto-credit points', () async {
      await container.read(journeyControllerProvider.notifier).createJourney(
            focus: JourneyFocus.nutrition,
            totalDays: 7,
          );

      await container.read(walletControllerProvider.notifier).loadWalletData();
      final initialBalance = container.read(walletControllerProvider).balance;

      final journeyBefore = container.read(journeyControllerProvider).journey!;
      final taskId = journeyBefore.todayRecord!.tasks.first.id;

      // Complete task
      final completeOk = await container.read(journeyControllerProvider.notifier).completeTask(
            taskId: taskId,
            activityId: 'meal_log_123',
          );
      expect(completeOk, isTrue);

      final journeyAfter = container.read(journeyControllerProvider).journey!;
      final completedTask = journeyAfter.todayRecord!.tasks.firstWhere((t) => t.id == taskId);
      expect(completedTask.isCompleted, isTrue);
      expect(completedTask.activityId, 'meal_log_123');

      // Rule: Completing task DOES NOT auto-award points!
      await container.read(walletControllerProvider.notifier).loadWalletData();
      final updatedBalance = container.read(walletControllerProvider).balance;
      expect(updatedBalance, initialBalance, reason: 'Points must NOT be auto-credited on task completion');
    });

    test('Claiming daily reward awards 20 SP and updates wallet balance', () async {
      await container.read(journeyControllerProvider.notifier).createJourney(
            focus: JourneyFocus.nutrition,
            totalDays: 7,
          );

      final journey = container.read(journeyControllerProvider).journey!;
      final taskId = journey.todayRecord!.tasks.first.id;

      // Complete the required task so the day is completed
      await container.read(journeyControllerProvider.notifier).completeTask(
            taskId: taskId,
            activityId: 'meal_log_123',
          );

      await container.read(walletControllerProvider.notifier).loadWalletData();
      final initialBalance = container.read(walletControllerProvider).balance;

      // Claim daily reward
      final claimOk = await container.read(journeyControllerProvider.notifier).claimDailyReward(
            date: journey.todayRecord!.date,
          );
      expect(claimOk, isTrue);

      final updatedJourney = container.read(journeyControllerProvider).journey!;
      expect(updatedJourney.todayRecord!.isDailyRewardClaimed, isTrue);

      // Verify wallet updated with 20 SP
      await container.read(walletControllerProvider.notifier).loadWalletData();
      final updatedBalance = container.read(walletControllerProvider).balance;
      expect(updatedBalance, initialBalance + 20);
    });

    test('Idempotency: Claiming daily reward twice does not re-award points', () async {
      await container.read(journeyControllerProvider.notifier).createJourney(
            focus: JourneyFocus.nutrition,
            totalDays: 7,
          );

      final journey = container.read(journeyControllerProvider).journey!;
      final taskId = journey.todayRecord!.tasks.first.id;

      await container.read(journeyControllerProvider.notifier).completeTask(taskId: taskId);

      // First claim
      await container.read(journeyControllerProvider.notifier).claimDailyReward(
            date: journey.todayRecord!.date,
          );
      await container.read(walletControllerProvider.notifier).loadWalletData();
      final balanceAfterFirst = container.read(walletControllerProvider).balance;

      // Duplicate claim attempt
      await container.read(journeyControllerProvider.notifier).claimDailyReward(
            date: journey.todayRecord!.date,
          );
      await container.read(walletControllerProvider.notifier).loadWalletData();
      final balanceAfterSecond = container.read(walletControllerProvider).balance;

      expect(balanceAfterSecond, equals(balanceAfterFirst));
    });

    test('onActivityCompleted triggers matching task completion', () async {
      await container.read(journeyControllerProvider.notifier).createJourney(
            focus: JourneyFocus.hybrid,
            totalDays: 7,
          );

      // Trigger workout activity completion
      await container.read(journeyControllerProvider.notifier).onActivityCompleted(
            type: JourneyTaskType.workout,
            activityId: 'session_workout_456',
          );

      final journey = container.read(journeyControllerProvider).journey!;
      final workoutTask = journey.todayRecord!.tasks.firstWhere((t) => t.type == JourneyTaskType.workout);
      expect(workoutTask.isCompleted, isTrue);
      expect(workoutTask.activityId, 'session_workout_456');
    });

    test('Wallet redemption fails for unavailable AI credit package without consumer (0 points deducted)', () async {
      await container.read(walletControllerProvider.notifier).loadWalletData();
      final initialWallet = container.read(walletControllerProvider);
      expect(initialWallet.balance, 240);
      expect(initialWallet.aiCredits, 3);

      final rewardItem = initialWallet.catalog.firstWhere((r) => r.id == 'rew_ai_credit_1');
      expect(rewardItem.isAvailable, isFalse);

      final success = await container.read(walletControllerProvider.notifier).redeemReward(rewardItem);
      expect(success, isFalse);

      final updatedState = container.read(walletControllerProvider);
      expect(updatedState.balance, 240, reason: 'Balance must not change');
      expect(updatedState.aiCredits, 3, reason: 'AI credits must not change');
      expect(updatedState.errorMessage, contains('chưa khả dụng'));
    });

    test('Wallet redemption succeeds when item is enabled as available (1 AI credit = 100 points)', () async {
      fakeRepo.setItemAvailable('rew_ai_credit_1', true);
      await container.read(walletControllerProvider.notifier).loadWalletData();
      final initialWallet = container.read(walletControllerProvider);
      expect(initialWallet.balance, 240);
      expect(initialWallet.aiCredits, 3);

      final rewardItem = initialWallet.catalog.firstWhere((r) => r.id == 'rew_ai_credit_1');
      expect(rewardItem.isAvailable, isTrue);

      final success = await container.read(walletControllerProvider.notifier).redeemReward(rewardItem);
      expect(success, isTrue);

      final updatedState = container.read(walletControllerProvider);
      expect(updatedState.balance, 140); // 240 - 100
      expect(updatedState.aiCredits, 4);  // 3 + 1
      expect(updatedState.transactions.first.type, 'reward_redemption');
      expect(updatedState.transactions.first.amount, -100);
    });

    test('Wallet redemption fails for unavailable item without deducting points', () async {
      await container.read(walletControllerProvider.notifier).loadWalletData();
      final initialWallet = container.read(walletControllerProvider);

      final unavailableItem = initialWallet.catalog.firstWhere((r) => r.id == 'rew_champion_badge');
      expect(unavailableItem.isAvailable, isFalse);

      final success = await container.read(walletControllerProvider.notifier).redeemReward(unavailableItem);
      expect(success, isFalse);

      final updatedState = container.read(walletControllerProvider);
      expect(updatedState.balance, initialWallet.balance, reason: 'Balance must not change for unavailable item');
      expect(updatedState.errorMessage, contains('chưa khả dụng'));
    });

    test('Wallet redemption fails with error message when balance is insufficient', () async {
      fakeRepo.setItemAvailable('rew_ai_credit_3', true);
      await container.read(walletControllerProvider.notifier).loadWalletData();
      final initialWallet = container.read(walletControllerProvider);

      // rew_ai_credit_3 costs 280, balance is 240
      final expensiveItem = initialWallet.catalog.firstWhere((r) => r.id == 'rew_ai_credit_3');
      final success = await container.read(walletControllerProvider.notifier).redeemReward(expensiveItem);

      expect(success, isFalse);
      final updatedState = container.read(walletControllerProvider);
      expect(updatedState.errorMessage, contains('không đủ'));
    });
  });

  group('Journey Widget Tests', () {
    late FakeJourneyRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeJourneyRepository();
    });

    Widget createTestApp(Widget child) {
      return ProviderScope(
        overrides: [
          journeyRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: child,
        ),
      );
    }

    testWidgets('CreateJourneyScreen renders all options and "Để sau" action works', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        createTestApp(
          CreateJourneyScreen(
            onDismiss: () => dismissed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tạo hành trình'), findsOneWidget);
      expect(find.text('Thói quen nhỏ, thay đổi bền lâu.'), findsOneWidget);
      expect(find.text('Bạn muốn tập trung vào điều gì?'), findsOneWidget);
      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('Dinh dưỡng'), findsOneWidget);
      expect(find.text('Kết hợp cả hai'), findsOneWidget);
      expect(find.text('Thời gian cam kết?'), findsOneWidget);
      expect(find.text('7 ngày'), findsOneWidget);
      expect(find.text('14 ngày'), findsOneWidget);
      expect(find.text('30 ngày'), findsOneWidget);
      expect(find.text('Bắt đầu hành trình'), findsOneWidget);

      // Tap "Để sau"
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets('SamanJourneyCard renders invitation when no active journey', (tester) async {
      bool tapCreate = false;

      await tester.pumpWidget(
        createTestApp(
          SamanJourneyCard(
            onCreateJourneyTap: () => tapCreate = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HÀNH TRÌNH SAMAN'), findsOneWidget);
      expect(find.text('Khởi đầu thói quen & Bứt phá mục tiêu'), findsOneWidget);
      expect(find.text('Tham gia ngay'), findsOneWidget);

      await tester.tap(find.text('Tham gia ngay'));
      expect(tapCreate, isTrue);
    });

    testWidgets('SamanJourneyCard renders streak & tasks when journey is active', (tester) async {
      await fakeRepo.createJourney(focus: JourneyFocus.hybrid, totalDays: 21);

      await tester.pumpWidget(
        createTestApp(
          const SamanJourneyCard(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('KẾT HỢP CẢ HAI'), findsOneWidget);
      expect(find.text('Chuỗi 0 ngày'), findsOneWidget);
      expect(find.text('Xem chi tiết hành trình'), findsOneWidget);
    });

    testWidgets('MyJourneyScreen renders daily missions without checkboxes and calendar', (tester) async {
      await fakeRepo.createJourney(focus: JourneyFocus.hybrid, totalDays: 21);

      await tester.pumpWidget(
        createTestApp(
          const MyJourneyScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hành trình của tôi'), findsOneWidget);
      expect(find.text('Mỗi ngày một tốt hơn'), findsOneWidget);
      expect(find.text('Hôm nay'), findsNWidgets(2));
      expect(find.text('Ghi nhận bữa ăn'), findsOneWidget);
      expect(find.text('Hoàn thành buổi tập'), findsOneWidget);
      expect(find.text('Lịch hành trình'), findsOneWidget);
      expect(find.text('Ví điểm & Lượt AI'), findsOneWidget);

      // Verify NO checkboxes exist
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('WalletRewardsScreen displays dual balance and shows disabled CTA when items are unavailable', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const WalletRewardsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ví điểm & Lượt AI'), findsOneWidget);
      expect(find.text('Điểm tích lũy'), findsOneWidget);
      expect(find.text('240'), findsOneWidget);
      expect(find.text('3 lượt AI'), findsNWidgets(2));
      expect(find.text('Đổi lượt AI'), findsOneWidget);
      expect(find.text('1 lượt AI'), findsOneWidget);
      expect(find.text('Lịch sử giao dịch'), findsOneWidget);

      // Verify sticky CTA displays unavailable state
      expect(find.text('Các gói đổi sắp ra mắt'), findsOneWidget);
    });

    testWidgets('WalletRewardsScreen opens confirmation sheet when an available item is selected', (tester) async {
      fakeRepo.setItemAvailable('rew_ai_credit_1', true);
      await tester.pumpWidget(
        createTestApp(
          const WalletRewardsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sticky CTA
      expect(find.text('Đổi 1 lượt AI với 100 điểm'), findsOneWidget);

      // Tap CTA to open Confirmation Bottom Sheet
      await tester.tap(find.text('Đổi 1 lượt AI với 100 điểm'));
      await tester.pumpAndSettle();

      expect(find.text('Đổi 1 lượt AI?'), findsOneWidget);
      expect(find.text('Sử dụng 100 điểm'), findsOneWidget);
      expect(find.text('Sau khi đổi: 140 điểm · 4 lượt AI'), findsOneWidget);
      expect(find.text('Xác nhận đổi'), findsOneWidget);
    });
  });
}
