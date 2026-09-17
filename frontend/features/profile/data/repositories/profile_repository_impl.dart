// [File: lib/features/profile/data/repositories/profile_repository_impl.dart]
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ✅ CÁC IMPORT TUYỆT ĐỐI (Fix toàn bộ lỗi uri_does_not_exist)
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/data/models/profile_model.dart'; 

class ProfileRepositoryImpl implements IProfileRepository {
  final http.Client _client;
  
  ProfileRepositoryImpl({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<ProfileEntity> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Ưu tiên load từ Local
    final localJson = prefs.getString('cached_profile');
    if (localJson != null) {
      try {
        return ProfileModel.fromJson(jsonDecode(localJson));
      } catch (e) {
        // Nếu json lỗi, bỏ qua
      }
    }
    
    // 2. Nếu local rỗng hoặc lỗi, thử gọi API
    try {
      final token = prefs.getString('auth_token');
      // Nếu chưa login thì trả về rỗng ngay
      if (token == null) return ProfileEntity.empty();

      final response = await _client.get(
        Uri.parse('${ApiConfig.baseUrl}/api/user/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (response.statusCode == 200) {
        final remoteData = ProfileModel.fromJson(jsonDecode(response.body));
        // Save ngược lại cache
        await prefs.setString('cached_profile', jsonEncode(remoteData.toJson()));
        return remoteData;
      }
    } catch (e) {
      // Log lỗi nhưng không crash app
      print("⚠️ Sync Error: $e");
    }

    // 3. Trả về profile mặc định
    return ProfileEntity.empty(); 
  }

  @override
  Future<void> saveProfile(ProfileEntity profile) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Chuyển Entity -> Model để có hàm toJson()
    final model = ProfileModel.fromEntity(profile);

    // 1. Lưu Local ngay lập tức
    await prefs.setString('cached_profile', jsonEncode(model.toJson()));

    // 2. Sync lên Server
    try {
      final token = prefs.getString('auth_token');
      if (token != null) {
        await _client.put(
          Uri.parse('${ApiConfig.baseUrl}/api/user/profile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode(model.toJson()),
        );
      }
    } catch (e) {
      print("⚠️ Sync Failed: $e");
    }
  }
}