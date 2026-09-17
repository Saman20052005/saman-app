import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageNotifier extends StateNotifier<Locale> {
  LanguageNotifier() : super(const Locale('vi')) {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('language_code') ?? 'vi';
    state = Locale(langCode);
  }

  Future<void> changeLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
    state = Locale(code);
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, Locale>((ref) {
  return LanguageNotifier();
});

class AppTranslations {
  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // Home Screen
      'hello': 'Hello',
      'quick_access': 'QUICK ACCESS',
      'discover': 'DISCOVER',
      'nutrition': 'Nutrition',
      'nutrition_sub': 'Meal plans',
      'workout': 'Workout',
      'workout_sub': 'Daily exercises',
      'plans': 'Plans',
      'plans_sub': '30 days plan',
      'report': 'Report',
      'report_sub': 'Statistics',
      'log_meal': 'Log Meal',
      'start_train': 'Start',
      'water': 'Water',
      'note': 'Note',
      'what_to_eat': 'What to eat?',
      'lets_train': "Let's train",
      'new_challenge': 'New challenge',
      'coming_soon': 'Feature coming soon!',

      // Profile Screen
      'profile_title': 'Profile',
      'body_stats': 'Body Stats',
      'age': 'Age',
      'height': 'Height',
      'weight': 'Weight',
      'goal_lifestyle': 'Goal & Lifestyle',
      'main_goal': 'Main Goal',
      'activity_level': 'Activity Level',
      'gender': 'Gender',
      'medical_notes': 'Medical Notes',
      'allergies_hint': 'Allergies, injuries...',
      'change_pass': 'Change Password',
      'language': 'Language',
      'logout': 'Log Out',
      'save_changes': 'Save Changes',
      'dark_mode': 'Dark Mode',
      'light_mode': 'Light Mode',
      'old_pass': 'Old Password',
      'new_pass': 'New Password',
      'confirm_pass': 'Confirm New Password',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'success': 'Success',
      'update_success': 'Profile updated successfully!',
      'login_required': 'Please login again',
      'connection_error': 'Connection error',
      'server_error': 'Server error',

      // Options (Keys)
      'male': 'Male',
      'female': 'Female',
      'other': 'Other',
      'low': 'Low',
      'medium': 'Medium',
      'high': 'High',
      'lose_weight': 'Lose Weight',
      'maintain_weight': 'Maintain Weight',
      'gain_muscle': 'Gain Muscle',
      'en': 'English',
      'vi': 'Vietnamese',
    },
    'vi': {
      // Home Screen
      'hello': 'Xin chào',
      'quick_access': 'TRUY CẬP NHANH',
      'discover': 'KHÁM PHÁ',
      'nutrition': 'Dinh dưỡng',
      'nutrition_sub': 'Thực đơn ăn uống',
      'workout': 'Tập luyện',
      'workout_sub': 'Bài tập hàng ngày',
      'plans': 'Kế hoạch',
      'plans_sub': 'Thử thách 30 ngày',
      'report': 'Báo cáo',
      'report_sub': 'Thống kê chỉ số',
      'log_meal': 'Ghi món',
      'start_train': 'Tập ngay',
      'water': 'Nước',
      'note': 'Ghi chú',
      'what_to_eat': 'Ăn gì hôm nay?',
      'lets_train': "Tập thôi nào",
      'new_challenge': 'Thử thách mới',
      'coming_soon': 'Tính năng đang phát triển!',

      // Profile Screen
      'profile_title': 'Hồ sơ cá nhân',
      'body_stats': 'Chỉ số cơ thể',
      'age': 'Tuổi',
      'height': 'Chiều cao',
      'weight': 'Cân nặng',
      'goal_lifestyle': 'Mục tiêu & Lối sống',
      'main_goal': 'Mục tiêu chính',
      'activity_level': 'Mức độ vận động',
      'gender': 'Giới tính',
      'medical_notes': 'Ghi chú y tế',
      'allergies_hint': 'Dị ứng, chấn thương...',
      'change_pass': 'Đổi mật khẩu',
      'language': 'Ngôn ngữ',
      'logout': 'Đăng xuất',
      'save_changes': 'Lưu thay đổi',
      'dark_mode': 'Chế độ Tối',
      'light_mode': 'Chế độ Sáng',
      'old_pass': 'Mật khẩu cũ',
      'new_pass': 'Mật khẩu mới',
      'confirm_pass': 'Xác nhận mật khẩu mới',
      'cancel': 'Hủy',
      'confirm': 'Xác nhận',
      'success': 'Thành công',
      'update_success': 'Đã cập nhật hồ sơ thành công!',
      'login_required': 'Vui lòng đăng nhập lại',
      'connection_error': 'Lỗi kết nối',
      'server_error': 'Lỗi máy chủ',

      // Options (Keys)
      'male': 'Nam',
      'female': 'Nữ',
      'other': 'Khác',
      'low': 'Ít',
      'medium': 'Vừa',
      'high': 'Nhiều',
      'lose_weight': 'Giảm cân',
      'maintain_weight': 'Giữ cân',
      'gain_muscle': 'Tăng cơ',
      'en': 'Tiếng Anh',
      'vi': 'Tiếng Việt',
    },
  };

  static String text(String key, Locale locale) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }
}
