import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/workout_plan.dart';
import '../../data/repositories/workout_repository_impl.dart';

part 'workout_controller.g.dart';

// 1. Controller quản lý danh sách bài tập (Giữ nguyên)
@riverpod
class WorkoutController extends _$WorkoutController {
  @override
  Future<List<WorkoutPlan>> build() async {
    return _fetchPlans();
  }

  Future<List<WorkoutPlan>> _fetchPlans() async {
    final repository = ref.read(workoutRepositoryProvider);
    return await repository.getWorkoutPlans();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchPlans());
  }
}

// 2. Controller xử lý Logic Log Workout (Action)
// 🔥 FIX: Loại bỏ việc quản lý state để tránh lỗi "Future already completed"
@riverpod
class WorkoutActionController extends _$WorkoutActionController {
  @override
  FutureOr<void> build() {
    // Không làm gì cả, chỉ dùng class này để chứa hàm logWorkout
  }

  Future<bool> logWorkout({
    required String planId,
    required int durationSeconds,
    required List<Map<String, dynamic>> exerciseLogs,
    int? caloriesBurned,
  }) async {
    // ❌ XÓA: state = const AsyncValue.loading(); -> UI đã có Dialog lo việc này

    try {
      // 🔥 [DEBUG] IN RA GIÁ TRỊ NHẬN ĐƯỢC TỪ UI
      print("🔥🔥🔥 CONTROLLER INPUT - Duration: $durationSeconds seconds");
      print("🔥🔥🔥 CONTROLLER INPUT - Calories passed: $caloriesBurned");
      final endTime = DateTime.now();
      final startTime = endTime.subtract(Duration(seconds: durationSeconds));

      // Tính toán Calories
      final int finalCalories;
      if (caloriesBurned != null) {
        finalCalories = caloriesBurned;
      } else {
        final double estimated =
            durationSeconds > 0 ? (durationSeconds / 60.0) * 7.0 : 0.0;
        finalCalories = estimated.round();
        // 🔥 [DEBUG] IN RA KẾT QUẢ TÍNH TOÁN
        print(
            "🔥🔥🔥 CALCULATED CALORIES: $estimated -> Round: $finalCalories");
      }

      final repository = ref.read(workoutRepositoryProvider);

      // Gọi Repository
      final success = await repository.logWorkout(
        planId: planId,
        durationSeconds: durationSeconds,
        exerciseLogs: exerciseLogs,
        startTime: startTime,
        endTime: endTime,
        caloriesBurned: finalCalories,
      );

      if (success) {
        // ❌ XÓA: state = const AsyncValue.data(null); -> Nguyên nhân gây lỗi Bad State

        // ✅ Chỉ Invalidate để làm mới dữ liệu nền
        // Dùng Future.delayed nhỏ để tách luồng hoàn toàn, tránh UI giật cục
        Future.delayed(const Duration(milliseconds: 100), () {
          ref.invalidate(workoutControllerProvider);
          ref.invalidate(weeklyStreakProvider);
        });
      }

      return success; // Trả về true/false thuần túy
    } catch (e) {
      // ❌ XÓA: state = AsyncValue.error(e, stack);
      // Ném lỗi ra ngoài để UI (try-catch bên màn hình Active) bắt được và hiện Toast
      rethrow;
    }
  }
}

// 3. Provider Functional lấy Streak (Giữ nguyên)
@riverpod
Future<List<bool>> weeklyStreak(Ref ref) async {
  final repository = ref.read(workoutRepositoryProvider);
  return await repository.getWeeklyStreak();
}
