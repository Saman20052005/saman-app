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

final localeProvider = languageProvider;

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
      'logged_meals_heading': 'Logged meals',
      'meal_story': 'Meal Story',
      'empty_meals_eyebrow': 'DAILY FOOD JOURNAL',
      'empty_meals_title': 'Your next healthy habit',
      'empty_meals_today': 'No meals logged today.',
      'empty_meals_other_day': 'No meals logged for this day.',
      'empty_meals_supporting': 'Start with your first meal.',
      'quick_log_title': 'Quick log',
      'quick_log_subtitle': 'Choose a meal to get started',
      'meal_type_breakfast': 'Breakfast',
      'meal_type_lunch': 'Lunch',
      'meal_type_dinner': 'Dinner',
      'meal_type_snack': 'Snack',
      'your_usuals_title': 'Your usuals',
      'your_usuals_recent': 'Recent',
      'your_usuals_favorites': 'Favorites',
      'your_usuals_review_portion': 'Review portion',
      'your_usuals_empty_recent_title': 'No recent meals',
      'your_usuals_empty_recent_desc': 'Start by logging your first meal.',
      'your_usuals_empty_favorites_title': 'No favorite meals',
      'your_usuals_empty_favorites_desc': 'Tap the heart icon on any recent food to save it.',
      'your_usuals_error': 'Could not load usual foods',
      'your_usuals_retry': 'Retry',
      'favorite_added': 'Added to favorites',
      'favorite_removed': 'Removed from favorites',
      'start_train': 'Start',
      'water': 'Water',
      'note': 'Note',
      'what_to_eat': 'What to eat?',
      'lets_train': "Let's train",
      'new_challenge': 'New challenge',
      'coming_soon': 'Feature coming soon!',

      // Nutrition AI Model Selection
      'model_core_3': 'Core 3',
      'model_pro_3': 'Pro 3',
      'model_core_3_desc': 'Quick lookup • Reference database',
      'model_pro_3_desc': 'Multi-dish recognition • Vietnamese food support',
      'model_core_3_accessibility': 'Core 3 model: Standard photo analysis',
      'model_pro_3_accessibility': 'Pro 3 model: Advanced AI analysis',
      'nutrition_mode_switch_to_core': 'Switch to Core 3',
      'nutrition_mode_suggest_core': '💡 Tip: You can switch to Core 3 mode and try analyzing again.',

      // Navigation Tabs
      'tab_home': 'Home',
      'tab_workout': 'Workout',
      'tab_saman': 'Saman',
      'tab_nutrition': 'Nutrition',
      'tab_profile': 'Profile',

      // Membership Pricing & Details
      'summary_free_sub': 'Core essentials',
      'summary_plus_sub': 'Nutrition AI',
      'summary_pro_sub': 'Workout Intelligence',
      'summary_ultra_sub': 'Personalized Intelligence',
      'per_month': '/ month',
      'per_year': '/ year',
      'equiv_to': 'Equivalent to',
      'explore_plus': 'Explore Plus',
      'explore_plus_sub': 'Nutrition AI details & allowances',
      'explore_pro': 'Explore Pro',
      'explore_pro_sub': 'Workout CV & rep analysis roadmap',
      'recommended_badge_mixed': 'Recommended',
      'explore_ultra': 'Explore Ultra',
      'explore_ultra_sub': 'Advanced Thinking & 5× allowance',

      // Manage Membership Details & FAQs
      'everyday_tracking_essentials': 'Your everyday tracking essentials.',
      'benefit_nutrition_logging': 'Nutrition logging',
      'benefit_nutrition_logging_sub': 'Keep a record of your meals.',
      'benefit_workout_tracking': 'Manual workout tracking',
      'benefit_workout_tracking_sub': 'Log your workouts manually.',
      'benefit_food_analysis': 'Free food photo analysis',
      'benefit_food_analysis_sub': 'Use the existing free analysis model.',
      'benefit_basic_metrics': 'Basic health metrics',
      'benefit_basic_metrics_sub': 'Track your core health measurements.',
      'faq_q1': 'What does my Free plan include?',
      'faq_a1':
          'Nutrition logging, manual workout tracking, the existing free food photo analysis model, and basic health metrics.',
      'faq_q2': 'Can I upgrade now?',
      'faq_a2':
          'Paid memberships are Coming Soon. You can explore the planned benefits, but this preview does not purchase or activate a plan.',
      'faq_q3': 'Are prices and AI limits final?',
      'faq_a3':
          'No. Displayed prices are demo estimates, and AI limits will be announced. Features, limits, and pricing may change before launch.',

      // Coach Persona & Drawer
      'coach_persona': 'Coach Persona',
      'coach_persona_desc': 'Coaching tone & response style',
      'view_all_conversations': 'View all conversations',
      'persona_updated': 'Coach persona updated successfully!',

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
      'logout': 'Log out',
      'logout_confirm_title': 'Log out',
      'logout_confirm_msg': 'Are you sure you want to log out?',
      'logout_dialog_saman_msg':
          'Are you sure you want to log out of your Saman account?',
      'no_notifications': 'No new notifications. You are on track!',
      'profile_health_details': 'Profile & Health Details',
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

      // Avatar & Profile Details (LOC-03)
      'avatar_dialog_title': 'Profile Photo',
      'choose_gallery': 'Choose from gallery',
      'use_google_photo': 'Use Google photo',
      'avatar_preview_title': 'Avatar Preview',
      'avatar_update_success': 'Avatar updated successfully!',
      'avatar_crop_hint': 'Image will be centered and cropped into a circle',
      'save_avatar': 'Save Profile Photo',
      'personal_info': 'Personal Information',
      'health_metrics': 'Health Metrics',
      'age_label': 'Age',
      'height_label': 'Height',
      'weight_label': 'Weight',
      'activity_level_label': 'Activity Level',
      'fitness_goal_label': 'Fitness Goal',
      'edit_profile': 'Edit Profile',
      'your_saman_profile': 'Your Saman profile',
      'your_goal': 'YOUR GOAL',
      'your_details': 'YOUR DETAILS',
      'activity_level_heading': 'ACTIVITY LEVEL',
      'account_heading': 'ACCOUNT',
      'profile_incomplete_notice': 'Profile incomplete',
      'journey_rewards_heading': 'JOURNEY & REWARDS',
      'my_journey_title': 'Saman Journey',
      'wallet_rewards_title': 'Rewards & AI Credits',
      'manage_membership': 'Manage membership',
      'error_load_profile': "We couldn't load your profile. Please check connection and retry.",
      'try_again': 'Try again',

      // Validation Errors (LOC-03)
      'val_age_range': 'Age must be between 10 and 120',
      'val_height_range': 'Height must be between 50cm and 250cm',
      'val_weight_range': 'Weight must be between 20kg and 300kg',

      // Settings & Preferences (LOC-03)
      'settings_title': 'Settings',
      'theme_setting': 'Theme',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'theme_system': 'System',

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
      'restore_purchases_action': 'Restore purchases',
      'auto_renew_active': 'Auto-renew active',
      'auto_renew_canceled': 'Auto-renew canceled',
      'in_grace_period_notice': 'Billing issue: In grace period',
      'active_until_notice': 'Active until',
      'quota_exhausted_title': 'Monthly AI quota reached',
      'quota_exhausted_desc':
          'You have used your monthly AI quota. Upgrade or wait for the reset.',
      'entitlement_required_title': 'Plus Membership Required',
      'entitlement_required_desc':
          'Advanced nutrition photo analysis is available with Plus membership.',
      'view_plus_plan': 'Explore Plus',
      'quota_usage_label': 'Scans used this month',

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
      'membership_banner_desc': 'Explore Plus, Pro, and Ultra',
      'membership_card_badge_preview': 'PREVIEW',
      'membership_card_badge_updated': 'Updated',
      'membership_card_desc_preview': 'Explore Plus, Pro, and Ultra',
      'membership_card_desc_active': 'Active plan: {plan}',
      'membership_card_cta_explore': 'Explore plans',
      'membership_card_cta_upgrade': 'View upgrade options',
      'membership_card_cta_your_plan': 'View your plan',
      'manage_membership_nav': 'Manage membership',
      'free_plan_status': 'Free plan',

      // Upgrade Sheets
      'current_plan_free_badge': 'CURRENT PLAN: FREE',
      'overview_free_desc':
          'Your account stays on Free with core tracking. Paid plans are Coming Soon.',
      'upgrade_sheet_plus_title': 'Upgrade to Plus',
      'upgrade_sheet_pro_title': 'Upgrade to Pro',
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

      // Saman Journal & Community
      'journal_title': 'Saman Journal',
      'journal_search_placeholder': 'Search knowledge, exercises, food...',
      'journal_tab_discover': 'Discover',
      'journal_tab_library': 'Library',
      'journal_tab_handbook': 'Handbook',
      'journal_topic_all': 'All',
      'journal_topic_workout': 'Workout',
      'journal_topic_nutrition': 'Nutrition',
      'journal_topic_recovery': 'Recovery',
      'journal_topic_habits': 'Habits',
      'journal_filter_all': 'All',
      'journal_filter_articles': 'Articles',
      'journal_filter_exercises': 'Exercises',
      'journal_filter_foods': 'Foods',
      'journal_filter_recipes': 'Recipes',
      'journal_continue_reading': 'Continue reading',
      'journal_sample_badge': 'SAMPLE DATA',
      'journal_sample_progress_note':
          'This is sample data for layout preview. Personal reading history sync is not enabled in this version.',
      'journal_food_preview_note':
          'Food nutrition preview mode. Quick-add does not commit to Nutrition meal logs without confirmation.',
      'journal_libraries': 'Libraries',
      'journal_view_all': 'View all',
      'journal_community_title': 'Saman Community',
      'journal_community_subtitle': 'Share your journey. Progress together.',
      'journal_community_cta': 'Explore community',

      // Community Translations
      'community_comment_send': 'Send comment',
      'community_cancel_reply': 'Cancel reply',
      'community_comment_retry': 'Retry',
      'community_comments_more': 'Load more comments / retry',
      'community_comments_order': 'Oldest first',
      'community_remote_comments_notice': 'Server mode • Comments and replies enabled',
      'community_comment_invalid': 'Enter 1–2000 characters.',
      'community_comment_access': 'This post is no longer accessible.',
      'community_comment_rejected': 'Comment rejected. Your draft is kept.',
      'community_question_invalid': 'Enter a title up to 150 characters and optional details up to 2000.',
      'community_audience_public': 'Public',
      'community_audience_followers': 'Followers',
      'community_audience_private': 'Only me',
      'community_attachment_duration_minutes': 'Minutes',
      'community_attachment_exercise_count': 'Exercises',
      'community_attachment_exercises': 'Exercise list',
      'community_attachment_foods': 'Foods',
      'community_attachment_set_count': 'Completed sets',
      'community_attachment_load_kg': 'Total load (kg)',
      'community_attachment_calories': 'Calories',
      'community_attachment_protein_grams': 'Protein (g)',
      'community_attachment_carbs_grams': 'Carbs (g)',
      'community_attachment_fat_grams': 'Fat (g)',
      'community_attachment_remove': 'Remove attachment',
      'community_attachment_review': 'The source changed. Review and attach a fresh preview before sharing.',
      'community_attachment_load_error': 'Unable to load owned activities. Your draft is retained.',
      'community_attachment_retry': 'Retry',
      'community_attachment_no_meal_duration': 'Meal logs do not provide duration.',
      'community_publish_current_user': 'Current account',
      'community_publish_invalid': 'Enter nonempty text up to 5000 characters.',
      'community_publish_rejected': 'Publication was rejected. Your draft is retained.',
      'community_publish_unconfirmed': 'Publishing is unconfirmed. Retry with the same content and request.',
      'community_publish_success': 'Published successfully.',
      'community_publish_media_unsupported': 'Media and activity attachments are not supported for publishing yet.',
      'community_publish_audience_unsupported': 'This audience is not supported. Choose Public, Followers or Only me.',
      'community_publish_audience': 'Who can see this?',
      'community_question_policy_pending': 'Question publishing policy is awaiting a decision.',
      'community_answer_hint': 'Share an answer or your experience...',
      'community_answer_send': 'Send answer',
      'community_answer_invalid': 'Enter 1–2000 characters.',
      'community_answer_unconfirmed': 'Answer is unconfirmed. Retry safely with the same request.',
      'community_answer_rejected': 'Answer was rejected. Your draft is retained.',
      'community_answer_access': 'This question is no longer accessible.',
      'community_answer_load_error': 'Could not load answers. Retry.',
      'community_vote_unconfirmed': 'Helpful vote is unconfirmed. Retry to reconcile.',
      'community_answers_more': 'Load more answers',
      'community_helpful_add': 'Mark helpful',
      'community_helpful_remove': 'Remove helpful vote',
      'community_comment_unconfirmed': 'Sending is unconfirmed. Retry safely with the same request.',
      'community_comments_load_error': 'Cannot load comments. Please retry.',

      'community_title': 'Saman Community',
      'community_feed': 'Community Feed',
      'community_discover': 'Community Explore',
      'community_for_you': 'For you',
      'community_following': 'Following',
      'community_qa': 'Q&A',
      'community_view_workout': 'View workout',
      'community_join_discussion': 'Join discussion',
      'community_post_detail': 'Post detail',
      'community_write_comment': 'Write a comment...',
      'community_replying_to': 'Replying to',
      'community_all_caught_up': 'You are all caught up!',

      // Community Feed & Filter Tabs
      'community_tab_all': 'All',
      'community_tab_following': 'Following',
      'community_tab_qa': 'Q&A',
      'community_empty_feed': 'No posts yet',
      'community_create_post_hint': 'What\'s on your mind?',

      // Post Card & Actions
      'post_action_like': 'Like',
      'post_action_comment': 'Comment',
      'post_action_save': 'Save',
      'post_action_share': 'Share',
      'post_action_delete': 'Delete post',
      'post_action_report': 'Report post',
      'delete_post_confirm_title': 'Delete Post',
      'delete_post_confirm_msg': 'Are you sure you want to delete this post?',
      'delete_post_success': 'Post deleted successfully',

      // Post Detail
      'post_detail_title': 'Post',
      'post_detail_comments_header': 'Comments',
      'post_detail_write_comment': 'Write a comment...',
      'post_detail_empty_comments': 'No comments yet. Be the first to comment!',
      'post_not_found_title': 'This post does not exist or has been deleted',
      'post_back_to_feed': 'Back to Feed',

      // Compose Flow
      'compose_post_title': 'Create Post',
      'compose_publish_btn': 'Publish',
      'compose_audience_public': 'Public',
      'compose_audience_followers': 'Followers only',
      'compose_audience_private': 'Private',
      'compose_discard_draft_title': 'Discard post?',
      'compose_discard_draft_msg': 'Your draft will be discarded.',
      'compose_keep_editing': 'Keep editing',
      'compose_discard': 'Discard',
      'select_media_title': 'Select Photo',

      // Nutrition Subsystem (LOC-04)
      'nutrition_title': 'Nutrition',
      'meal_suggestion_title': 'Meal Suggestions',
      'meal_logged_success': 'Meal logged to journal!',
      'confirm_and_log': 'Confirm & Log',
      'missing_profile_info': 'Missing Profile information',
      'missing_profile_desc':
          'Please update personal details to calculate nutrition goals.',
      'update_profile_now': 'Update now',
      'macro_calories': 'Calories',
      'macro_protein': 'Protein',
      'macro_carbs': 'Carbs',
      'macro_fat': 'Fat',
      'meal_breakfast': 'Breakfast',
      'meal_lunch': 'Lunch',
      'meal_dinner': 'Dinner',
      'meal_snack': 'Snacks',
      'log_meal_btn': 'Log Meal',
      'meal_plan_heading': 'MEAL PLAN',
      'no_meal_plan_badge': 'NO MEAL PLAN',
      'create_meal_plan_ai': 'Create meal plan with AI',
      'create_plan_btn': 'Create Plan',
      'load_nutrition_failed': 'Could not load nutrition data',

      // Workout Subsystem (LOC-04)
      'workout_title': 'Workout',
      'workout_home_subtitle': 'Train, log & explore movements',
      'my_plans': 'My Plans',
      'today_scheduled_session': 'TODAY’S SCHEDULED SESSION',
      'start_workout': 'Start workout',
      'view_plan': 'View plan',
      'quick_start': 'Quick start',
      'quick_start_desc': 'Train without a plan',
      'browse_library': 'Browse library',
      'explore_exercises': 'Explore exercises',
      'train_by_focus': 'TRAIN BY FOCUS',
      'all_categories': 'All categories',
      'your_plan': 'YOUR PLAN',
      'view_full_plan': 'View full plan',
      'last_workout': 'LAST WORKOUT',
      'view_history': 'View history',
      'no_saved_workouts': 'No saved workouts yet',
      'rest_timer': 'Rest Timer',
      'next_exercise': 'Next Exercise',
      'log_set': 'Log Set',
      'finish_workout': 'Finish Workout',
      'sets_completed': 'Sets Completed',
      'workout_summary_title': 'Workout Summary',
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
      'logged_meals_heading': 'Bữa ăn đã ghi',
      'meal_story': 'Meal Story',
      'empty_meals_eyebrow': 'NHẬT KÝ DINH DƯỠNG',
      'empty_meals_title': 'Bắt đầu thói quen ăn uống lành mạnh',
      'empty_meals_today': 'Hôm nay bạn chưa ghi bữa ăn nào.',
      'empty_meals_other_day': 'Chưa có bữa ăn nào được ghi cho ngày này.',
      'empty_meals_supporting': 'Bắt đầu với bữa ăn đầu tiên của bạn.',
      'quick_log_title': 'Ghi nhanh',
      'quick_log_subtitle': 'Chọn bữa ăn để bắt đầu',
      'meal_type_breakfast': 'Sáng',
      'meal_type_lunch': 'Trưa',
      'meal_type_dinner': 'Tối',
      'meal_type_snack': 'Ăn nhẹ',
      'your_usuals_title': 'Món quen của bạn',
      'your_usuals_recent': 'Gần đây',
      'your_usuals_favorites': 'Yêu thích',
      'your_usuals_review_portion': 'Xem khẩu phần',
      'your_usuals_empty_recent_title': 'Chưa có món gần đây',
      'your_usuals_empty_recent_desc': 'Bắt đầu bằng việc ghi bữa ăn đầu tiên.',
      'your_usuals_empty_favorites_title': 'Chưa có món yêu thích',
      'your_usuals_empty_favorites_desc': 'Chạm vào biểu tượng trái tim ở món gần đây để lưu.',
      'your_usuals_error': 'Không thể tải món ăn quen thuộc',
      'your_usuals_retry': 'Thử lại',
      'favorite_added': 'Đã thêm vào yêu thích',
      'favorite_removed': 'Đã bỏ yêu thích',
      'start_train': 'Tập ngay',
      'water': 'Nước',
      'note': 'Ghi chú',
      'what_to_eat': 'Ăn gì hôm nay?',
      'lets_train': "Tập thôi nào",
      'new_challenge': 'Thử thách mới',
      'coming_soon': 'Tính năng đang phát triển!',

      // Nutrition AI Model Selection
      'model_core_3': 'Core 3',
      'model_pro_3': 'Pro 3',
      'model_core_3_desc': 'Tra cứu nhanh • Cơ sở dữ liệu tham chiếu',
      'model_pro_3_desc': 'Nhận diện đa món • Hỗ trợ món ăn Việt',
      'model_core_3_accessibility': 'Model Core 3: Phân tích ảnh tiêu chuẩn',
      'model_pro_3_accessibility': 'Model Pro 3: Phân tích AI nâng cao',
      'nutrition_mode_switch_to_core': 'Đổi sang Core 3',
      'nutrition_mode_suggest_core': '💡 Gợi ý: Bạn có thể chuyển sang chế độ Core 3 và thử phân tích lại.',

      // Navigation Tabs
      'tab_home': 'Trang chủ',
      'tab_workout': 'Tập luyện',
      'tab_saman': 'Saman',
      'tab_nutrition': 'Dinh dưỡng',
      'tab_profile': 'Hồ sơ',

      // Membership Pricing & Details
      'summary_free_sub': 'Tính năng cơ bản thiết yếu',
      'summary_plus_sub': 'AI dinh dưỡng',
      'summary_pro_sub': 'Thị giác máy tập luyện',
      'summary_ultra_sub': 'Trí tuệ cá nhân hóa cao cấp',
      'per_month': '/ tháng',
      'per_year': '/ năm',
      'equiv_to': 'Tương đương',
      'explore_plus': 'Khám phá Plus',
      'explore_plus_sub': 'Chi tiết AI dinh dưỡng & hạn mức',
      'explore_pro': 'Khám phá Pro',
      'explore_pro_sub': 'Thị giác máy tập luyện & đếm rep',
      'recommended_badge_mixed': 'Được đề xuất',
      'explore_ultra': 'Khám phá Ultra',
      'explore_ultra_sub': 'Tư duy nâng cao & hạn mức gấp 5 lần',

      // Manage Membership Details & FAQs
      'everyday_tracking_essentials': 'Các tính năng theo dõi thiết yếu hàng ngày.',
      'benefit_nutrition_logging': 'Ghi nhật ký dinh dưỡng',
      'benefit_nutrition_logging_sub': 'Ghi lại các bữa ăn của bạn.',
      'benefit_workout_tracking': 'Theo dõi tập luyện thủ công',
      'benefit_workout_tracking_sub': 'Tự ghi chép các buổi tập của bạn.',
      'benefit_food_analysis': 'Phân tích ảnh món ăn miễn phí',
      'benefit_food_analysis_sub': 'Dùng mô hình phân tích cơ bản có sẵn.',
      'benefit_basic_metrics': 'Chỉ số sức khỏe cơ bản',
      'benefit_basic_metrics_sub': 'Theo dõi các chỉ số cơ thể trọng yếu.',
      'faq_q1': 'Gói Miễn phí của tôi bao gồm những gì?',
      'faq_a1':
          'Ghi nhật ký dinh dưỡng, theo dõi bài tập thủ công, phân tích ảnh món ăn miễn phí và các chỉ số sức khỏe cơ bản.',
      'faq_q2': 'Tôi có thể nâng cấp ngay bây giờ không?',
      'faq_a2':
          'Các gói trả phí sắp ra mắt. Bạn có thể khám phá quyền lợi dự kiến, nhưng bản xem trước này chưa thể mua hoặc kích hoạt gói.',
      'faq_q3': 'Giá và hạn mức AI đã là chính thức chưa?',
      'faq_a3':
          'Chưa. Mức giá hiển thị là ước tính thử nghiệm và hạn mức AI sẽ được thông báo sau. Tính năng, hạn mức và giá có thể thay đổi trước khi ra mắt.',

      // Coach Persona & Drawer
      'coach_persona': 'Phong cách Coach',
      'coach_persona_desc': 'Tông giọng & phong cách phản hồi',
      'view_all_conversations': 'Xem tất cả cuộc trò chuyện',
      'persona_updated': 'Đã cập nhật phong cách Coach thành công!',

      // Profile Screen
      'profile_title': 'Hồ sơ',
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
      'logout_confirm_title': 'Đăng xuất',
      'logout_confirm_msg': 'Bạn có chắc chắn muốn đăng xuất không?',
      'logout_dialog_saman_msg':
          'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản Saman không?',
      'no_notifications':
          'Không có thông báo mới. Bạn đang theo sát kế hoạch!',
      'profile_health_details': 'Hồ sơ & Thông tin Sức khỏe',
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

      // Avatar & Profile Details (LOC-03)
      'avatar_dialog_title': 'Ảnh đại diện',
      'choose_gallery': 'Chọn từ thư viện',
      'use_google_photo': 'Dùng ảnh Google',
      'avatar_preview_title': 'Xem trước ảnh đại diện',
      'avatar_update_success': 'Cập nhật ảnh đại diện thành công!',
      'avatar_crop_hint': 'Ảnh sẽ được căn giữa và cắt theo khung tròn',
      'save_avatar': 'Lưu ảnh đại diện',
      'personal_info': 'Thông tin cá nhân',
      'health_metrics': 'Chỉ số sức khỏe',
      'age_label': 'Tuổi',
      'height_label': 'Chiều cao',
      'weight_label': 'Cân nặng',
      'activity_level_label': 'Mức độ vận động',
      'fitness_goal_label': 'Mục tiêu thể hình',
      'edit_profile': 'Chỉnh sửa hồ sơ',
      'your_saman_profile': 'Hồ sơ Saman của bạn',
      'your_goal': 'MỤC TIÊU CỦA BẠN',
      'your_details': 'THÔNG TIN CỦA BẠN',
      'activity_level_heading': 'MỨC ĐỘ VẬN ĐỘNG',
      'account_heading': 'TÀI KHOẢN',
      'profile_incomplete_notice': 'Hồ sơ chưa hoàn thiện',
      'journey_rewards_heading': 'HÀNH TRÌNH & ĐIỂM THƯỞNG',
      'my_journey_title': 'Hành trình Saman',
      'wallet_rewards_title': 'Điểm thưởng & Đổi lượt AI',
      'manage_membership': 'Quản lý gói hội viên',
      'error_load_profile':
          'Không thể tải hồ sơ. Vui lòng kiểm tra kết nối và thử lại.',
      'try_again': 'Thử lại',

      // Validation Errors (LOC-03)
      'val_age_range': 'Tuổi phải từ 10 đến 120',
      'val_height_range': 'Chiều cao phải từ 50cm đến 250cm',
      'val_weight_range': 'Cân nặng phải từ 20kg đến 300kg',

      // Settings & Preferences (LOC-03)
      'settings_title': 'Cài đặt',
      'theme_setting': 'Giao diện',
      'theme_light': 'Sáng',
      'theme_dark': 'Tối',
      'theme_system': 'Hệ thống',

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
      'restore_purchases_action': 'Khôi phục gói mua',
      'auto_renew_active': 'Tự động gia hạn: Đang bật',
      'auto_renew_canceled': 'Đã hủy tự động gia hạn',
      'in_grace_period_notice': 'Sự cố thanh toán: Đang trong thời gian ân hạn',
      'active_until_notice': 'Còn hạn đến',
      'quota_exhausted_title': 'Đã dùng hết hạn mức AI tháng',
      'quota_exhausted_desc':
          'Bạn đã dùng hết hạn mức phân tích AI tháng này. Nâng cấp hoặc chờ chu kỳ tiếp theo.',
      'entitlement_required_title': 'Yêu cầu gói Hội viên Plus',
      'entitlement_required_desc':
          'Phân tích ảnh dinh dưỡng nâng cao khả dụng với gói Plus.',
      'view_plus_plan': 'Khám phá gói Plus',
      'quota_usage_label': 'Lượt phân tích đã dùng tháng này',
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
      'membership_banner_title': 'Saman Membership',
      'membership_banner_desc': 'Tìm hiểu các gói Plus, Pro và Ultra',
      'membership_card_badge_preview': 'Xem trước',
      'membership_card_badge_updated': 'Có cập nhật',
      'membership_card_desc_preview': 'Tìm hiểu các gói Plus, Pro và Ultra',
      'membership_card_desc_active': 'Gói đang hoạt động: {plan}',
      'membership_card_cta_explore': 'Khám phá các gói',
      'membership_card_cta_upgrade': 'Xem gói nâng cấp',
      'membership_card_cta_your_plan': 'Xem gói của bạn',
      'manage_membership_nav': 'Quản lý hội viên',
      'free_plan_status': 'Gói Miễn phí',

      // Upgrade Sheets
      'current_plan_free_badge': 'GÓI HIỆN TẠI: MIỄN PHÍ',
      'overview_free_desc':
          'Tài khoản của bạn duy trì gói Miễn phí với các tính năng theo dõi cơ bản. Các gói trả phí sẽ sớm ra mắt.',
      'upgrade_sheet_plus_title': 'Nâng cấp lên Plus',
      'upgrade_sheet_pro_title': 'Nâng cấp lên Pro',
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

      // Saman Journal & Community
      'journal_title': 'Saman Journal',
      'journal_search_placeholder': 'Tìm kiến thức, bài tập, món ăn…',
      'journal_tab_discover': 'Khám phá',
      'journal_tab_library': 'Thư viện',
      'journal_tab_handbook': 'Cẩm nang',
      'journal_topic_all': 'Tất cả',
      'journal_topic_workout': 'Tập luyện',
      'journal_topic_nutrition': 'Dinh dưỡng',
      'journal_topic_recovery': 'Phục hồi',
      'journal_topic_habits': 'Thói quen',
      'journal_filter_all': 'Tất cả',
      'journal_filter_articles': 'Bài viết',
      'journal_filter_exercises': 'Bài tập',
      'journal_filter_foods': 'Thực phẩm',
      'journal_filter_recipes': 'Công thức',
      'journal_continue_reading': 'Tiếp tục đọc',
      'journal_sample_badge': 'DỮ LIỆU MẪU',
      'journal_sample_progress_note':
          'Đây là dữ liệu mẫu để minh họa giao diện. Tính năng đồng bộ lịch sử đọc của người dùng chưa được kích hoạt trong phiên bản này.',
      'journal_food_preview_note':
          'Chế độ xem trước thông tin dinh dưỡng. Nút thêm nhanh chưa ghi nhận món ăn vào nhật ký Nutrition khi chưa qua luồng xác nhận.',
      'journal_libraries': 'Thư viện',
      'journal_view_all': 'Xem tất cả',
      'journal_community_title': 'Saman Community',
      'journal_community_subtitle': 'Chia sẻ hành trình. Cùng nhau tiến bộ.',
      'journal_community_cta': 'Khám phá cộng đồng',

      // Community Translations
      'community_comment_send': 'Gửi bình luận',
      'community_cancel_reply': 'Hủy trả lời',
      'community_comment_retry': 'Thử lại',
      'community_comments_more': 'Tải thêm bình luận / thử lại',
      'community_comments_order': 'Cũ nhất trước',
      'community_remote_comments_notice': 'Chế độ máy chủ • Đã bật bình luận và trả lời',
      'community_comment_invalid': 'Nhập từ 1–2000 ký tự.',
      'community_comment_access': 'Bạn không còn quyền truy cập bài viết này.',
      'community_comment_rejected': 'Bình luận bị từ chối. Nội dung đang soạn được giữ lại.',
      'community_question_invalid': 'Nhập tiêu đề tối đa 150 ký tự và chi tiết không bắt buộc tối đa 2000 ký tự.',
      'community_audience_public': 'Công khai',
      'community_audience_followers': 'Người theo dõi',
      'community_audience_private': 'Chỉ mình tôi',
      'community_attachment_duration_minutes': 'Phút',
      'community_attachment_exercise_count': 'Số bài tập',
      'community_attachment_exercises': 'Danh sách bài tập',
      'community_attachment_foods': 'Thành phần món ăn',
      'community_attachment_set_count': 'Số hiệp',
      'community_attachment_load_kg': 'Tổng tải (kg)',
      'community_attachment_calories': 'Calo',
      'community_attachment_protein_grams': 'Đạm (g)',
      'community_attachment_carbs_grams': 'Tinh bột (g)',
      'community_attachment_fat_grams': 'Chất béo (g)',
      'community_attachment_remove': 'Bỏ đính kèm',
      'community_attachment_review': 'Nguồn đã thay đổi. Xem lại và đính kèm preview mới trước khi đăng.',
      'community_attachment_load_error': 'Không tải được hoạt động chính chủ. Đã giữ nội dung đang soạn.',
      'community_attachment_retry': 'Thử lại',
      'community_attachment_no_meal_duration': 'Nhật ký bữa ăn không có thời lượng.',
      'community_publish_current_user': 'Tài khoản hiện tại',
      'community_publish_invalid': 'Nhập nội dung không rỗng, tối đa 5000 ký tự.',
      'community_publish_rejected': 'Yêu cầu đăng bị từ chối. Đã giữ nội dung đang soạn.',
      'community_publish_unconfirmed': 'Chưa xác nhận kết quả đăng. Thử lại với cùng nội dung và yêu cầu.',
      'community_publish_success': 'Đã đăng thành công.',
      'community_publish_media_unsupported': 'Chưa hỗ trợ đăng ảnh và đính kèm hoạt động.',
      'community_publish_audience_unsupported': 'Chưa hỗ trợ đối tượng này. Chọn Công khai, Người theo dõi hoặc Chỉ mình tôi.',
      'community_publish_audience': 'Ai có thể xem?',
      'community_question_policy_pending': 'Đang chờ quyết định chính sách đăng câu hỏi.',
      'community_answer_hint': 'Nhập câu trả lời hoặc kinh nghiệm của bạn...',
      'community_answer_send': 'Gửi câu trả lời',
      'community_answer_invalid': 'Nhập từ 1–2000 ký tự.',
      'community_answer_unconfirmed': 'Chưa xác nhận câu trả lời. Thử lại an toàn với cùng yêu cầu.',
      'community_answer_rejected': 'Câu trả lời bị từ chối. Đã giữ nội dung nhập.',
      'community_answer_access': 'Bạn không còn quyền xem câu hỏi này.',
      'community_answer_load_error': 'Không tải được câu trả lời. Vui lòng thử lại.',
      'community_vote_unconfirmed': 'Chưa xác nhận bình chọn. Thử lại để đối chiếu.',
      'community_answers_more': 'Tải thêm câu trả lời',
      'community_helpful_add': 'Đánh dấu hữu ích',
      'community_helpful_remove': 'Bỏ bình chọn hữu ích',
      'community_comment_unconfirmed': 'Chưa xác nhận kết quả gửi. Thử lại an toàn với cùng yêu cầu.',
      'community_comments_load_error': 'Không tải được bình luận. Vui lòng thử lại.',

      'community_title': 'Saman Community',
      'community_feed': 'Bảng tin cộng đồng',
      'community_discover': 'Khám phá cộng đồng',
      'community_for_you': 'Dành cho bạn',
      'community_following': 'Đang theo dõi',
      'community_qa': 'Hỏi đáp',
      'community_view_workout': 'Xem buổi tập',
      'community_join_discussion': 'Tham gia thảo luận',
      'community_post_detail': 'Chi tiết bài viết',
      'community_write_comment': 'Viết bình luận...',
      'community_replying_to': 'Đang trả lời',
      'community_all_caught_up': 'Bạn đã xem hết các bài viết mới!',

      // Community Feed & Filter Tabs
      'community_tab_all': 'Tất cả',
      'community_tab_following': 'Đang theo dõi',
      'community_tab_qa': 'Hỏi & Đáp',
      'community_empty_feed': 'Chưa có bài viết nào',
      'community_create_post_hint': 'Bạn đang nghĩ gì?',

      // Post Card & Actions
      'post_action_like': 'Thích',
      'post_action_comment': 'Bình luận',
      'post_action_save': 'Lưu',
      'post_action_share': 'Chia sẻ',
      'post_action_delete': 'Xóa bài viết',
      'post_action_report': 'Báo cáo nội dung',
      'delete_post_confirm_title': 'Xóa bài viết',
      'delete_post_confirm_msg': 'Bạn có chắc chắn muốn xóa bài viết này không?',
      'delete_post_success': 'Đã xóa bài viết thành công',

      // Post Detail
      'post_detail_title': 'Bài viết',
      'post_detail_comments_header': 'Bình luận',
      'post_detail_write_comment': 'Viết bình luận...',
      'post_detail_empty_comments': 'Chưa có bình luận nào. Hãy là người đầu tiên!',
      'post_not_found_title': 'Bài viết này không tồn tại hoặc đã bị xóa',
      'post_back_to_feed': 'Quay lại Bảng tin',

      // Compose Flow
      'compose_post_title': 'Tạo bài viết',
      'compose_publish_btn': 'Đăng',
      'compose_audience_public': 'Công khai',
      'compose_audience_followers': 'Chỉ người theo dõi',
      'compose_audience_private': 'Riêng tư',
      'compose_discard_draft_title': 'Hủy bài viết?',
      'compose_discard_draft_msg': 'Nội dung bạn đang viết sẽ bị mất.',
      'compose_keep_editing': 'Tiếp tục viết',
      'compose_discard': 'Hủy',
      'select_media_title': 'Chọn ảnh',

      // Nutrition Subsystem (LOC-04)
      'nutrition_title': 'Dinh dưỡng',
      'meal_suggestion_title': 'Gợi ý bữa ăn',
      'meal_logged_success': 'Đã ghi nhận bữa ăn vào nhật ký!',
      'confirm_and_log': 'Xác nhận & Ghi nhật ký',
      'missing_profile_info': 'Thiếu thông tin Profile',
      'missing_profile_desc':
          'Vui lòng cập nhật thông tin cá nhân để tính toán mục tiêu dinh dưỡng.',
      'update_profile_now': 'Cập nhật ngay',
      'macro_calories': 'Calo',
      'macro_protein': 'Đạm',
      'macro_carbs': 'Tinh bột',
      'macro_fat': 'Chất béo',
      'meal_breakfast': 'Bữa sáng',
      'meal_lunch': 'Bữa trưa',
      'meal_dinner': 'Bữa tối',
      'meal_snack': 'Bữa phụ',
      'log_meal_btn': 'Ghi bữa ăn',
      'meal_plan_heading': 'KẾ HOẠCH BỮA ĂN',
      'no_meal_plan_badge': 'CHƯA CÓ KẾ HOẠCH',
      'create_meal_plan_ai': 'Tạo kế hoạch ăn uống với AI',
      'create_plan_btn': 'Tạo kế hoạch',
      'load_nutrition_failed': 'Không thể tải dữ liệu dinh dưỡng',

      // Workout Subsystem (LOC-04)
      'workout_title': 'Tập luyện',
      'workout_home_subtitle': 'Tập luyện, ghi nhật ký & khám phá chuyển động',
      'my_plans': 'Kế hoạch của tôi',
      'today_scheduled_session': 'BUỔI TẬP ĐÃ LÊN LỊCH HÔM NAY',
      'start_workout': 'Bắt đầu tập',
      'view_plan': 'Xem kế hoạch',
      'quick_start': 'Bắt đầu nhanh',
      'quick_start_desc': 'Tập không theo kế hoạch',
      'browse_library': 'Duyệt thư viện',
      'explore_exercises': 'Khám phá bài tập',
      'train_by_focus': 'TẬP THEO NHÓM CƠ',
      'all_categories': 'Tất cả danh mục',
      'your_plan': 'KẾ HOẠCH CỦA BẠN',
      'view_full_plan': 'Xem toàn bộ kế hoạch',
      'last_workout': 'BUỔI TẬP GẦN NHẤT',
      'view_history': 'Xem lịch sử',
      'no_saved_workouts': 'Chưa có buổi tập nào',
      'rest_timer': 'Thời gian nghỉ',
      'next_exercise': 'Bài tập tiếp theo',
      'log_set': 'Ghi hiệp',
      'finish_workout': 'Hoàn thành buổi tập',
      'sets_completed': 'Hiệp đã hoàn thành',
      'workout_summary_title': 'Tổng kết buổi tập',
    },
  };

  static String text(String key, Locale locale) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}

extension AppTranslationsX on BuildContext {
  String tr(String key) {
    final locale = Localizations.maybeLocaleOf(this);
    if (locale != null) {
      return AppTranslations.text(key, locale);
    }
    return AppTranslations.text(key, const Locale('en'));
  }
}

