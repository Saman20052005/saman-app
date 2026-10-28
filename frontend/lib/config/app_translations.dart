import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguageMode {
  system,
  vi,
  en,
}

class LanguageNotifier extends StateNotifier<Locale> {
  LanguageNotifier() : super(const Locale('vi')) {
    _loadLanguage();
  }

  AppLanguageMode _mode = AppLanguageMode.system;
  AppLanguageMode get currentMode => _mode;

  static Locale resolveSystemLocale() {
    try {
      final code = WidgetsBinding
          .instance.platformDispatcher.locale.languageCode
          .toLowerCase();
      if (code == 'vi') {
        return const Locale('vi');
      }
    } catch (_) {}
    return const Locale('en');
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString('language_mode');
      if (modeStr == 'vi') {
        _mode = AppLanguageMode.vi;
        state = const Locale('vi');
      } else if (modeStr == 'en') {
        _mode = AppLanguageMode.en;
        state = const Locale('en');
      } else if (modeStr == 'system') {
        _mode = AppLanguageMode.system;
        state = resolveSystemLocale();
      } else {
        final langCode = prefs.getString('language_code');
        if (langCode == 'en') {
          _mode = AppLanguageMode.en;
          state = const Locale('en');
        } else if (langCode == 'vi') {
          _mode = AppLanguageMode.vi;
          state = const Locale('vi');
        } else {
          _mode = AppLanguageMode.system;
          state = resolveSystemLocale();
        }
      }
    } catch (_) {
      state = resolveSystemLocale();
    }
  }

  Future<void> changeLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == 'system') {
      _mode = AppLanguageMode.system;
      final resolved = resolveSystemLocale();
      await prefs.setString('language_mode', 'system');
      await prefs.setString('language_code', resolved.languageCode);
      state = resolved;
    } else {
      _mode = code == 'en' ? AppLanguageMode.en : AppLanguageMode.vi;
      await prefs.setString('language_mode', code);
      await prefs.setString('language_code', code);
      state = Locale(code);
    }
  }

  Future<void> setLanguageMode(AppLanguageMode mode) async {
    switch (mode) {
      case AppLanguageMode.system:
        await changeLanguage('system');
        break;
      case AppLanguageMode.vi:
        await changeLanguage('vi');
        break;
      case AppLanguageMode.en:
        await changeLanguage('en');
        break;
    }
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, Locale>((ref) {
  return LanguageNotifier();
});

final languageModeProvider = Provider<AppLanguageMode>((ref) {
  ref.watch(languageProvider);
  return ref.read(languageProvider.notifier).currentMode;
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
      'edit_profile_title': 'Edit Profile',
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

      // Membership
      'membership_compare_title': 'Compare plans',
      'membership_preview_badge': 'MEMBERSHIP PREVIEW',
      'membership_find_your_fit': 'Find your fit.',
      'membership_find_your_fit_desc':
          'Compare the essentials and the intelligence planned for each tier.',
      'billing_monthly': 'Monthly',
      'billing_yearly': 'Yearly',
      'demo_pricing_disclaimer': 'Demo pricing · Subject to change',
      'paid_coming_soon_note': 'Plus, Pro, and Ultra are Coming Soon.',
      'status_legend_title': 'STATUS LEGEND',
      'legend_included_free': 'Included in Free',
      'legend_planned_inclusion': 'Planned inclusion',
      'legend_not_in_tier': 'Not in this tier',
      'feature_matrix_title': 'FEATURE MATRIX',
      'recommended_pro_badge': 'Recommended: Pro',
      'matrix_header_feature': 'Feature',
      'group_core_essentials': 'CORE ESSENTIALS',
      'group_nutrition_ai': 'NUTRITION AI',
      'group_workout_cv': 'WORKOUT CV INTELLIGENCE',
      'group_advanced_intel': 'ADVANCED INTELLIGENCE',
      'explore_plan_details_title': 'EXPLORE PLAN DETAILS',
      'paid_notice_footer':
          'Paid memberships are not available yet. Features, limits, and prices may change before launch.',
      'coming_soon_btn': 'Coming Soon',
      'back_to_membership': 'Back to Membership',
      'preview_only_notice': 'Preview only · Your account stays on Free',
      'also_included': 'Also included',
      'baseline_active': 'Baseline Active',
      'tier_inherited': 'Tier Inherited',
      'roadmap_badge': 'Roadmap',
      'planned_with': 'Planned with',
      'current_badge': 'CURRENT',
      'recommended_badge': 'RECOMMENDED',
      'coming_soon_badge': 'COMING SOON',

      // Manage Membership
      'manage_membership_title': 'Manage membership',
      'account_badge': 'Account',
      'current_plan_heading': 'CURRENT PLAN',
      'no_paid_activated': 'No paid membership activated.',
      'your_free_benefits': 'Your Free benefits',
      'explore_whats_next': "Explore what's next.",
      'explore_whats_next_desc':
          'Discover planned Nutrition AI, Workout Intelligence, and personalized features across Plus, Pro, and Ultra.',
      'explore_plans_btn': 'Explore Plans',
      'membership_faq_title': 'Membership FAQ',
      'quiet_footer_notice':
          'Membership preview · Paid plans are not available yet.',

      // Coming Soon
      'coming_soon_hero_title': 'Something to look forward to.',
      'coming_soon_hero_desc':
          "This membership is not available yet. Explore what's planned while continuing with Free.",
      'youre_exploring': "YOU'RE EXPLORING",
      'account_stays_free_title': 'Your account stays on Free.',
      'account_stays_free_desc':
          'No payment has been taken and no paid membership has been activated.',
      'coming_soon_footer_note':
          'Planned features, limits, and pricing may change before launch.',

      // Membership Overview & Profile
      'membership_title': 'Membership',
      'membership_hero_title': 'Elevate your training.',
      'membership_hero_desc':
          'Explore planned tiers designed for nutrition intelligence and workout computer vision.',
      'compare_all_plans_btn': 'Compare all plans',
      'your_active_plan': 'Your Active Plan',
      'explore_tier_btn': 'Explore',
      'membership_banner_title': 'Saman Membership',
      'membership_banner_desc':
          'Explore upcoming intelligence tiers: Plus, Pro & Ultra. Your account stays on Free.',
      'manage_membership_nav': 'Manage membership',
      'free_plan_status': 'Free plan',

      // Upgrade Sheets
      'explore_nutrition_ai': 'Explore Nutrition AI',
      'explore_nutrition_ai_desc':
          'Discover planned Gemini food photo analysis with Saman Plus.',
      'explore_workout_intelligence': 'Explore Workout Intelligence',
      'explore_workout_intelligence_desc':
          'Discover planned Workout CV benefits with Saman Pro.',
      'gemini_food_photo_analysis': 'Gemini food photo analysis',
      'monthly_ai_allowance': 'Monthly AI allowance',
      'workout_cv_ai': 'Workout CV AI',
      'movement_analysis_rep_counting': 'Movement analysis and rep counting',
      'separate_cv_allowance': 'Separate Workout CV allowance',
      'limits_tba': 'Limits to be announced.',
      'badge_planned': 'Planned',
      'explore_plus_btn': 'Explore Plus',
      'explore_pro_btn': 'Explore Pro',
      'continue_with_free': 'Continue with Free',
      'back_to_workout': 'Back to Workout',
      'sheet_preview_notice':
          'Preview only · Paid memberships are not available yet.',

      // App Settings & Preferences
      'app_settings': 'App settings',
      'preferences': 'PREFERENCES',
      'language_setting': 'Ngôn ngữ / Language',
      'units': 'Units',
      'units_sub_metric': 'kg, cm',
      'units_sub_imperial': 'lb, ft/in',
      'unit_metric': 'Metric',
      'unit_imperial': 'Imperial',
      'metric_label': 'Metric — kg, cm',
      'imperial_label': 'Imperial — lb, ft/in',
      'use_device_language': 'Use device language',
      'device_language_sub': 'Match phone language settings',
      'about_saman': 'ABOUT SAMAN',
      'privacy_policy': 'Privacy policy',
      'terms_of_service': 'Terms of service',
      'help_support': 'Help & support',
      'app_information': 'APP INFORMATION',
      'app_version': 'App version',
      'app_tagline': 'Saman · Your fitness companion',
      'not_configured_title': 'Notice',
      'privacy_not_configured_desc':
          'The official Privacy policy will be updated in an upcoming release.',
      'terms_not_configured_desc':
          'The official Terms of service will be updated in an upcoming release.',
      'help_not_configured_desc':
          'Help & support channels will be available soon. For inquiries, please reach out via our community channels.',
      'close': 'Close',
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
      'edit_profile_title': 'Chỉnh sửa hồ sơ',
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

      // Membership
      'membership_compare_title': 'So sánh các gói',
      'membership_preview_badge': 'BẢN XEM TRƯỚC HỘI VIÊN',
      'membership_find_your_fit': 'Tìm gói phù hợp.',
      'membership_find_your_fit_desc':
          'So sánh tính năng thiết yếu và trí tuệ nhân tạo dự kiến cho từng gói.',
      'billing_monthly': 'Theo tháng',
      'billing_yearly': 'Theo năm',
      'demo_pricing_disclaimer': 'Giá thử nghiệm · Có thể thay đổi',
      'paid_coming_soon_note': 'Các gói Plus, Pro và Ultra sắp ra mắt.',
      'status_legend_title': 'CHÚ THÍCH TRẠNG THÁI',
      'legend_included_free': 'Đã có trong gói Miễn phí',
      'legend_planned_inclusion': 'Dự kiến tích hợp',
      'legend_not_in_tier': 'Không có trong gói này',
      'feature_matrix_title': 'BẢNG TÍNH NĂNG CHI TIẾT',
      'recommended_pro_badge': 'Được đề xuất: Pro',
      'matrix_header_feature': 'Tính năng',
      'group_core_essentials': 'TÍNH NĂNG CỐT LÕI',
      'group_nutrition_ai': 'TRÍ TUỆ NHÂN TẠO DINH DƯỠNG',
      'group_workout_cv': 'THỊ GIÁC MÁY TẬP LUYỆN',
      'group_advanced_intel': 'TRÍ TUỆ CAO CẤP',
      'explore_plan_details_title': 'KHÁM PHÁ CHI TIẾT GÓI',
      'paid_notice_footer':
          'Các gói trả phí chưa khả dụng. Tính năng, hạn mức và giá có thể thay đổi trước khi ra mắt.',
      'coming_soon_btn': 'Sắp ra mắt',
      'back_to_membership': 'Quay lại Hội viên',
      'preview_only_notice': 'Bản xem trước · Tài khoản vẫn giữ gói Miễn phí',
      'also_included': 'Bao gồm thêm',
      'baseline_active': 'Gói cơ bản đang hoạt động',
      'tier_inherited': 'Thừa hưởng từ gói trước',
      'roadmap_badge': 'Lộ trình',
      'planned_with': 'Dự kiến cùng',
      'current_badge': 'HIỆN TẠI',
      'recommended_badge': 'ĐƯỢC ĐỀ XUẤT',
      'coming_soon_badge': 'SẮP RA MẮT',
      'manage_membership_title': 'Quản lý hội viên',
      'account_badge': 'Tài khoản',
      'current_plan_heading': 'GÓI HIỆN TẠI',
      'no_paid_activated': 'Chưa kích hoạt gói trả phí nào.',
      'your_free_benefits': 'Quyền lợi gói Miễn phí của bạn',
      'explore_whats_next': 'Khám phá tính năng tiếp theo.',
      'explore_whats_next_desc':
          'Khám phá AI dinh dưỡng, trí tuệ tập luyện và cá nhân hóa trên Plus, Pro và Ultra.',
      'explore_plans_btn': 'Khám phá các gói',
      'membership_faq_title': 'Câu hỏi thường gặp',
      'quiet_footer_notice':
          'Bản xem trước hội viên · Các gói trả phí chưa khả dụng.',
      'coming_soon_hero_title': 'Điều đáng để chờ đợi.',
      'coming_soon_hero_desc':
          'Gói hội viên này chưa khả dụng. Bạn có thể khám phá lộ trình trong khi tiếp tục dùng gói Miễn phí.',
      'youre_exploring': 'BẠN ĐANG KHÁM PHÁ',
      'account_stays_free_title': 'Tài khoản vẫn giữ gói Miễn phí.',
      'account_stays_free_desc':
          'Chưa có khoản thanh toán nào được thực hiện và chưa kích hoạt gói trả phí nào.',
      'coming_soon_footer_note':
          'Tính năng dự kiến, hạn mức và giá có thể thay đổi trước khi ra mắt.',
      'membership_title': 'Hội viên',
      'membership_hero_title': 'Nâng tầm tập luyện.',
      'membership_hero_desc':
          'Khám phá các gói dự kiến với AI dinh dưỡng và thị giác máy tập luyện.',
      'compare_all_plans_btn': 'So sánh tất cả các gói',
      'your_active_plan': 'Gói đang hoạt động',
      'explore_tier_btn': 'Khám phá',
      'membership_banner_title': 'Hội viên Saman',
      'membership_banner_desc':
          'Khám phá các gói dự kiến: Plus, Pro & Ultra. Tài khoản vẫn Miễn phí.',
      'manage_membership_nav': 'Quản lý hội viên',
      'free_plan_status': 'Gói Miễn phí',

      // Upgrade Sheets
      'explore_nutrition_ai': 'Khám phá AI dinh dưỡng',
      'explore_nutrition_ai_desc':
          'Khám phá tính năng phân tích ảnh món ăn bằng Gemini với Saman Plus.',
      'explore_workout_intelligence': 'Khám phá thị giác máy tập luyện',
      'explore_workout_intelligence_desc':
          'Khám phá quyền lợi thị giác máy tập luyện với Saman Pro.',
      'gemini_food_photo_analysis': 'Phân tích ảnh món ăn với Gemini',
      'monthly_ai_allowance': 'Hạn mức AI theo tháng',
      'workout_cv_ai': 'AI thị giác máy tập luyện',
      'movement_analysis_rep_counting': 'Phân tích chuyển động và đếm số rep',
      'separate_cv_allowance': 'Hạn mức thị giác máy riêng biệt',
      'limits_tba': 'Hạn mức sẽ được thông báo sau.',
      'badge_planned': 'Dự kiến',
      'explore_plus_btn': 'Khám phá Plus',
      'explore_pro_btn': 'Khám phá Pro',
      'continue_with_free': 'Tiếp tục với bản Miễn phí',
      'back_to_workout': 'Quay lại bài tập',
      'sheet_preview_notice': 'Bản xem trước · Các gói trả phí chưa khả dụng.',

      // App Settings & Preferences
      'app_settings': 'Cài đặt ứng dụng',
      'preferences': 'TÙY CHỌN',
      'language_setting': 'Ngôn ngữ / Language',
      'units': 'Đơn vị đo',
      'units_sub_metric': 'kg, cm',
      'units_sub_imperial': 'lb, ft/in',
      'unit_metric': 'Hệ mét',
      'unit_imperial': 'Hệ Anh',
      'metric_label': 'Hệ mét — kg, cm',
      'imperial_label': 'Hệ Anh — lb, ft/in',
      'use_device_language': 'Theo ngôn ngữ thiết bị',
      'device_language_sub': 'Tự động theo cài đặt máy',
      'about_saman': 'VỀ SAMAN',
      'privacy_policy': 'Chính sách quyền riêng tư',
      'terms_of_service': 'Điều khoản dịch vụ',
      'help_support': 'Trợ giúp & hỗ trợ',
      'app_information': 'THÔNG TIN ỨNG DỤNG',
      'app_version': 'Phiên bản ứng dụng',
      'app_tagline': 'Saman · Người bạn đồng hành tập luyện',
      'not_configured_title': 'Thông báo',
      'privacy_not_configured_desc':
          'Chính sách quyền riêng tư chính thức sẽ được cập nhật trong bản phát hành tới.',
      'terms_not_configured_desc':
          'Điều khoản dịch vụ chính thức sẽ được cập nhật trong bản phát hành tới.',
      'help_not_configured_desc':
          'Kênh trợ giúp & hỗ trợ sẽ sớm được kích hoạt. Xin vui lòng liên hệ qua các kênh cộng đồng của chúng tôi.',
      'close': 'Đóng',
    },
  };

  static String text(String key, Locale locale) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}
