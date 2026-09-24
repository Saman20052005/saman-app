import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart';

abstract class ProfileLocalDataSource {
  Future<void> cacheProfile(ProfileModel profile);
  Future<ProfileModel?> getLastProfile();
}

class ProfileLocalDataSourceImpl implements ProfileLocalDataSource {
  final SharedPreferences? sharedPreferences;

  ProfileLocalDataSourceImpl({this.sharedPreferences});

  static const String CACHED_PROFILE_KEY = 'cached_profile';

  @override
  Future<void> cacheProfile(ProfileModel profile) {
    final prefs = sharedPreferences;
    if (prefs == null) return Future.value();

    return prefs.setString(
      CACHED_PROFILE_KEY,
      jsonEncode(profile.toJson()),
    );
  }

  @override
  Future<ProfileModel?> getLastProfile() async {
    final prefs = sharedPreferences;
    if (prefs == null) return null;

    final jsonString = prefs.getString(CACHED_PROFILE_KEY);
    if (jsonString != null) {
      return ProfileModel.fromJson(jsonDecode(jsonString));
    }
    return null;
  }
}
