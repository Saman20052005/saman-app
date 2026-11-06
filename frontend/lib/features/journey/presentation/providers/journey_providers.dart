import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/journey_repository.dart';
import '../../domain/models/journey_models.dart';

final journeyRepositoryProvider = Provider<JourneyRepository>((ref) {
  return JourneyRepositoryImpl();
});

class JourneyState {
  final bool isLoading;
  final bool isSaving;
  final bool isClaiming;
  final SamanJourney? journey;
  final String? errorMessage;
  final String? successMessage;

  const JourneyState({
    this.isLoading = false,
    this.isSaving = false,
    this.isClaiming = false,
    this.journey,
    this.errorMessage,
    this.successMessage,
  });

  bool get hasActiveJourney => journey != null && journey!.isActive;

  JourneyState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? isClaiming,
    SamanJourney? journey,
    bool clearJourney = false,
    String? errorMessage,
    String? successMessage,
  }) {
    return JourneyState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isClaiming: isClaiming ?? this.isClaiming,
      journey: clearJourney ? null : (journey ?? this.journey),
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class JourneyController extends StateNotifier<JourneyState> {
  final JourneyRepository _repository;
  final Ref _ref;

  JourneyController(this._repository, this._ref) : super(const JourneyState()) {
    loadActiveJourney();
  }

  Future<void> loadActiveJourney() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final j = await _repository.getActiveJourney();
      state = state.copyWith(isLoading: false, journey: j, clearJourney: j == null);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> createJourney({
    required JourneyFocus focus,
    required int totalDays,
    String? reminderTime,
  }) async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final newJourney = await _repository.createJourney(
        focus: focus,
        totalDays: totalDays,
        reminderTime: reminderTime,
      );
      state = state.copyWith(isSaving: false, journey: newJourney);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> completeTask({
    required String taskId,
    String? activityId,
  }) async {
    final cur = state.journey;
    if (cur == null) return false;

    try {
      final updated = await _repository.completeTask(
        journeyId: cur.id,
        taskId: taskId,
        activityId: activityId,
      );
      state = state.copyWith(journey: updated);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> claimDailyReward({String? date}) async {
    final cur = state.journey;
    if (cur == null) return false;

    state = state.copyWith(isClaiming: true, errorMessage: null, successMessage: null);
    try {
      final updated = await _repository.claimDailyReward(
        journeyId: cur.id,
        date: date,
      );
      state = state.copyWith(
        isClaiming: false,
        journey: updated,
        successMessage: 'Nhận thành công 20 điểm thưởng!',
      );
      // Refresh wallet after claiming points
      _ref.read(walletControllerProvider.notifier).loadWalletData();
      return true;
    } catch (e) {
      state = state.copyWith(isClaiming: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> onActivityCompleted({required JourneyTaskType type, String? activityId}) async {
    final cur = state.journey;
    if (cur == null || !cur.isActive) return;
    final today = cur.todayRecord;
    if (today == null) return;

    for (final task in today.tasks) {
      if (task.type == type && !task.isCompleted) {
        await completeTask(taskId: task.id, activityId: activityId);
        break;
      }
    }
  }

  void resetSession() {
    state = const JourneyState();
  }
}

final journeyControllerProvider = StateNotifierProvider<JourneyController, JourneyState>((ref) {
  final repo = ref.watch(journeyRepositoryProvider);
  return JourneyController(repo, ref);
});

class WalletState {
  final bool isLoading;
  final bool isRedeeming;
  final int balance;
  final int aiCredits;
  final List<PointTransaction> transactions;
  final List<RewardItem> catalog;
  final String? errorMessage;
  final String? successMessage;

  const WalletState({
    this.isLoading = false,
    this.isRedeeming = false,
    this.balance = 0,
    this.aiCredits = 0,
    this.transactions = const [],
    this.catalog = const [],
    this.errorMessage,
    this.successMessage,
  });

  WalletState copyWith({
    bool? isLoading,
    bool? isRedeeming,
    int? balance,
    int? aiCredits,
    List<PointTransaction>? transactions,
    List<RewardItem>? catalog,
    String? errorMessage,
    String? successMessage,
  }) {
    return WalletState(
      isLoading: isLoading ?? this.isLoading,
      isRedeeming: isRedeeming ?? this.isRedeeming,
      balance: balance ?? this.balance,
      aiCredits: aiCredits ?? this.aiCredits,
      transactions: transactions ?? this.transactions,
      catalog: catalog ?? this.catalog,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class WalletController extends StateNotifier<WalletState> {
  final JourneyRepository _repository;

  WalletController(this._repository) : super(const WalletState()) {
    loadWalletData();
  }

  Future<void> loadWalletData() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final balanceData = await _repository.getPointBalance();
      final txs = await _repository.getPointHistory();
      final cat = await _repository.getRewardsCatalog();
      state = state.copyWith(
        isLoading: false,
        balance: balanceData.balance,
        aiCredits: balanceData.aiCredits,
        transactions: txs,
        catalog: cat,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> redeemReward(RewardItem item) async {
    if (state.isRedeeming) return false;

    if (!item.isAvailable) {
      state = state.copyWith(errorMessage: 'Phần thưởng này hiện chưa khả dụng để đổi.');
      return false;
    }

    if (state.balance < item.pointsCost) {
      state = state.copyWith(errorMessage: 'Số dư Saman Points không đủ để đổi phần thưởng này.');
      return false;
    }

    state = state.copyWith(isRedeeming: true, errorMessage: null, successMessage: null);
    try {
      final ok = await _repository.redeemReward(rewardId: item.id);
      if (ok) {
        await loadWalletData();
        state = state.copyWith(
          isRedeeming: false,
          successMessage: 'Đổi thành công: ${item.title}',
        );
        return true;
      } else {
        state = state.copyWith(isRedeeming: false, errorMessage: 'Đổi phần thưởng thất bại.');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isRedeeming: false, errorMessage: e.toString());
      return false;
    }
  }

  void resetSession() {
    state = const WalletState();
  }
}

final walletControllerProvider = StateNotifierProvider<WalletController, WalletState>((ref) {
  final repo = ref.watch(journeyRepositoryProvider);
  return WalletController(repo);
});
