import '../../domain/models/journey_models.dart';
import 'journey_repository.dart';

class FakeJourneyRepository implements JourneyRepository {
  SamanJourney? activeJourney;
  int balance = 240;
  int aiCredits = 3;
  List<PointTransaction> transactions = [
    const PointTransaction(
      id: 'tx_init',
      userId: 'test_user',
      amount: 20,
      type: 'daily_reward',
      description: 'Thưởng hoàn thành ngày hôm qua',
      createdAt: '2026-10-27T20:30:00Z',
    ),
    const PointTransaction(
      id: 'tx_redeem_1',
      userId: 'test_user',
      amount: -100,
      type: 'reward_redemption',
      description: 'Đổi 1 lượt AI',
      createdAt: '2026-10-22T09:15:00Z',
    ),
  ];

  List<RewardItem> catalog = const [
    RewardItem(
      id: 'rew_ai_credit_1',
      title: '1 lượt AI',
      description: 'Phân tích ảnh món ăn hoặc tư vấn chuyên sâu cùng Saman Coach',
      pointsCost: 100,
      aiCredits: 1,
      category: 'ai_credit',
      iconName: 'smart_toy',
      isAvailable: false,
      statusNote: 'Chưa khả dụng · Đang kết nối hạ tầng AI quota',
    ),
    RewardItem(
      id: 'rew_ai_credit_3',
      title: '3 lượt AI',
      description: 'Gói tiết kiệm 3 lượt phân tích ảnh món ăn và tư vấn Coach',
      pointsCost: 280,
      aiCredits: 3,
      category: 'ai_credit',
      iconName: 'smart_toy',
      isAvailable: false,
      statusNote: 'Chưa khả dụng · Đang kết nối hạ tầng AI quota',
    ),
    RewardItem(
      id: 'rew_champion_badge',
      title: 'Huy hiệu Chiến binh Saman',
      description: 'Huy hiệu vinh danh độc quyền trên hồ sơ cá nhân',
      pointsCost: 500,
      aiCredits: 0,
      category: 'profile_perk',
      iconName: 'military_tech',
      isAvailable: false,
      statusNote: 'Chưa khả dụng trong phiên bản hiện tại',
    ),
  ];

  void setItemAvailable(String id, bool available) {
    catalog = catalog.map((item) {
      if (item.id == id) {
        return RewardItem(
          id: item.id,
          title: item.title,
          description: item.description,
          pointsCost: item.pointsCost,
          aiCredits: item.aiCredits,
          category: item.category,
          iconName: item.iconName,
          isAvailable: available,
          statusNote: available ? 'Khả dụng · Đổi ngay' : 'Chưa khả dụng trong phiên bản hiện tại',
        );
      }
      return item;
    }).toList();
  }

  @override
  Future<SamanJourney?> getActiveJourney() async {
    return activeJourney;
  }

  @override
  Future<SamanJourney> createJourney({
    required JourneyFocus focus,
    required int totalDays,
    String? reminderTime,
  }) async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final end = now.add(Duration(days: totalDays - 1));
    final endStr = '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';

    final tasks = <JourneyTask>[
      if (focus == JourneyFocus.nutrition || focus == JourneyFocus.hybrid)
        const JourneyTask(
          id: 'task_nutri_1',
          type: JourneyTaskType.nutrition,
          title: 'Ghi nhận bữa ăn',
          subtitle: 'Lưu ít nhất 1 bữa ăn trong ngày',
        ),
      if (focus == JourneyFocus.workout || focus == JourneyFocus.hybrid)
        const JourneyTask(
          id: 'task_workout_1',
          type: JourneyTaskType.workout,
          title: 'Hoàn thành buổi tập',
          subtitle: 'Thực hiện và lưu 1 buổi tập theo lịch',
        ),
    ];

    final todayRecord = JourneyDayRecord(
      date: todayStr,
      dayIndex: 1,
      isCompleted: false,
      isRestDay: false,
      isDailyRewardClaimed: false,
      dailyRewardPoints: 20,
      tasks: tasks,
      pointsEarned: 0,
    );

    final journey = SamanJourney(
      id: 'journey_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'test_user',
      focus: focus,
      totalDays: totalDays,
      startDate: todayStr,
      endDate: endStr,
      reminderTime: reminderTime,
      status: JourneyStatus.active,
      currentStreak: 0,       // Rule: streak starts at 0
      completedDaysCount: 0, // Rule: 0 completed days initially
      bestStreak: 0,
      pointsEarned: 0,
      todayRecord: todayRecord,
      days: [todayRecord],
    );

    activeJourney = journey;
    return journey;
  }

  @override
  Future<SamanJourney> completeTask({
    required String journeyId,
    required String taskId,
    String? activityId,
  }) async {
    final cur = activeJourney;
    if (cur == null) throw StateError('No active journey');

    final today = cur.todayRecord;
    if (today == null) throw StateError('No today record');

    final targetTask = today.tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw ArgumentError('Task not found'),
    );
    if (targetTask.isCompleted) {
      return cur;
    }

    final updatedTasks = today.tasks.map((t) {
      if (t.id == taskId) {
        return t.copyWith(isCompleted: true, activityId: activityId);
      }
      return t;
    }).toList();

    final allDone = updatedTasks.every((t) => t.isCompleted);
    final updatedToday = today.copyWith(
      tasks: updatedTasks,
      isCompleted: allDone,
    );

    final updatedDays = cur.days.map((d) => d.date == updatedToday.date ? updatedToday : d).toList();
    final completedCount = updatedDays.where((d) => d.isCompleted).length;

    final updated = cur.copyWith(
      todayRecord: updatedToday,
      days: updatedDays,
      completedDaysCount: completedCount,
      currentStreak: allDone ? (cur.currentStreak + 1) : cur.currentStreak,
      bestStreak: allDone ? (cur.bestStreak + 1) : cur.bestStreak,
    );

    activeJourney = updated;
    return updated;
  }

  @override
  Future<SamanJourney> claimDailyReward({
    required String journeyId,
    String? date,
  }) async {
    final cur = activeJourney;
    if (cur == null) throw StateError('No active journey');
    final today = cur.todayRecord;
    if (today == null) throw StateError('No today record');

    if (!today.isCompleted) {
      throw StateError('Daily tasks not completed');
    }
    if (today.isDailyRewardClaimed) {
      return cur;
    }

    final pts = today.dailyRewardPoints;
    balance += pts;

    final updatedToday = today.copyWith(
      isDailyRewardClaimed: true,
      pointsEarned: today.pointsEarned + pts,
    );

    transactions.insert(
      0,
      PointTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        userId: cur.userId,
        amount: pts,
        type: 'daily_reward',
        description: 'Thưởng hoàn thành Ngày ${today.dayIndex}',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );

    final updated = cur.copyWith(
      todayRecord: updatedToday,
      pointsEarned: cur.pointsEarned + pts,
      days: cur.days.map((d) => d.date == updatedToday.date ? updatedToday : d).toList(),
    );

    activeJourney = updated;
    return updated;
  }

  @override
  Future<WalletBalanceData> getPointBalance() async {
    return WalletBalanceData(balance: balance, aiCredits: aiCredits);
  }

  @override
  Future<List<PointTransaction>> getPointHistory() async {
    return List.unmodifiable(transactions);
  }

  @override
  Future<List<RewardItem>> getRewardsCatalog() async {
    return List.unmodifiable(catalog);
  }

  @override
  Future<bool> redeemReward({required String rewardId}) async {
    final item = catalog.firstWhere((r) => r.id == rewardId);
    if (!item.isAvailable) {
      throw StateError('Phần thưởng hiện chưa khả dụng');
    }
    if (balance < item.pointsCost) {
      return false;
    }

    balance -= item.pointsCost;
    aiCredits += item.aiCredits;

    transactions.insert(
      0,
      PointTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        userId: 'test_user',
        amount: -item.pointsCost,
        type: 'reward_redemption',
        description: 'Đổi phần thưởng: ${item.title}',
        createdAt: DateTime.now().toIso8601String(),
        referenceId: rewardId,
      ),
    );

    return true;
  }
}
