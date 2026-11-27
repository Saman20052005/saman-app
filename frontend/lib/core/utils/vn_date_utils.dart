// Pure date/time helpers normalized to Vietnam time (UTC+7, Asia/Ho_Chi_Minh).
// These functions do not depend on the host device's local timezone.

DateTime vnDateTime([DateTime? nowUtc]) {
  final vn = (nowUtc ?? DateTime.now().toUtc()).toUtc().add(
        const Duration(hours: 7),
      );
  return DateTime(
    vn.year,
    vn.month,
    vn.day,
    vn.hour,
    vn.minute,
    vn.second,
    vn.millisecond,
    vn.microsecond,
  );
}

DateTime vnTodayDate([DateTime? nowUtc]) {
  final vn = vnDateTime(nowUtc);
  return DateTime(vn.year, vn.month, vn.day);
}

String vnTodayIsoDate([DateTime? nowUtc]) {
  final vn = (nowUtc ?? DateTime.now().toUtc()).toUtc().add(
        const Duration(hours: 7),
      );
  final year = vn.year.toString().padLeft(4, '0');
  final month = vn.month.toString().padLeft(2, '0');
  final day = vn.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
