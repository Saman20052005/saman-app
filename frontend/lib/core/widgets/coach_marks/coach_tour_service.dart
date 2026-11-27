import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riverpod provider for [CoachTourService].
final coachTourServiceProvider = Provider<CoachTourService>(
  (ref) => CoachTourService(),
);

/// Manages persisted "has seen" state for per-screen Coach Marks tours.
class CoachTourService {
  CoachTourService({SharedPreferences? prefs}) : _prefs = prefs;

  static const String homeScreenId = 'home_v1';
  static const String nutritionScreenId = 'nutrition_v1';
  static const String workoutScreenId = 'workout_v1';

  static const List<String> allScreenIds = <String>[
    homeScreenId,
    nutritionScreenId,
    workoutScreenId,
  ];

  static const String _keyPrefix = 'has_seen_tour_';

  /// Global bypass flag for automated tests that do not want tours auto-shown.
  static bool isTestBypassEnabled = false;

  final SharedPreferences? _prefs;

  /// Returns the `SharedPreferences` key for [screenId].
  static String keyFor(String screenId) => '$_keyPrefix$screenId';

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? SharedPreferences.getInstance();
  }

  /// Returns `true` if the tour for [screenId] has not been seen yet.
  Future<bool> shouldShow(String screenId) async {
    if (isTestBypassEnabled) return false;
    final prefs = await _getPrefs();
    return !(prefs.getBool(keyFor(screenId)) ?? false);
  }

  /// Marks the tour for [screenId] as seen so it will not auto-show again.
  Future<void> markSeen(String screenId) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyFor(screenId), true);
  }

  /// Clears all persisted tour flags so every screen tour can be replayed.
  Future<void> resetAll() async {
    final prefs = await _getPrefs();
    for (final screenId in allScreenIds) {
      await prefs.remove(keyFor(screenId));
    }
    final dynamicKeys = prefs
        .getKeys()
        .where((key) => key.startsWith(_keyPrefix))
        .toList(growable: false);
    for (final key in dynamicKeys) {
      await prefs.remove(key);
    }
  }
}
