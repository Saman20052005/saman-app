class HourlyCalorieStats {
  final int hour;
  final double intake;
  final double burn;

  HourlyCalorieStats(
      {required this.hour, required this.intake, required this.burn});

  factory HourlyCalorieStats.fromJson(Map<String, dynamic> json) {
    final hourRaw = json['hour'] ?? json['h'] ?? json['hour_of_day'] ?? 0;
    final intakeRaw = json['intake'] ?? json['calories_in'] ?? json['in'] ?? 0;
    final burnRaw = json['burn'] ?? json['calories_out'] ?? json['out'] ?? 0;

    return HourlyCalorieStats(
      hour: int.tryParse(hourRaw.toString()) ?? 0,
      intake: double.tryParse(intakeRaw.toString()) ?? 0.0,
      burn: double.tryParse(burnRaw.toString()) ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() =>
      {'hour': hour, 'intake': intake, 'burn': burn};
}
