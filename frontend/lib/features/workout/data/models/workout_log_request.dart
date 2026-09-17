class WorkoutLogRequest {
  final String planName;
  final int durationSeconds;
  final List<Map<String, dynamic>> exercises;
  final DateTime startTime;
  final DateTime endTime;

  // 🔥 FIX: Đổi final double -> final int
  final int caloriesBurned;

  WorkoutLogRequest({
    required this.planName,
    required this.durationSeconds,
    required this.exercises,
    required this.startTime,
    required this.endTime,
    required this.caloriesBurned, // <--- SỬA TẠI ĐÂY
  });

  Map<String, dynamic> toJson() {
    return {
      "plan_name": planName,
      "duration_seconds": durationSeconds,
      "exercises": exercises,
      "start_time": startTime.toIso8601String(),
      "end_time": endTime.toIso8601String(),
      "calories_burned": caloriesBurned, // Int gửi đi vẫn là chuẩn JSON
    };
  }
}
