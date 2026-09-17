import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'history_provider.g.dart';

@riverpod
class LastWeightNotifier extends _$LastWeightNotifier {
  @override
  double build(String exerciseId) {
    // Truy vấn từ Hive hoặc shared_preferences
    // Tạm thời trả về 0, sau này implement database
    return 0.0;
  }
}
