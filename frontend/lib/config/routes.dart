import 'package:flutter/material.dart';
// Import các màn hình chính
import '../screens/splash_screen.dart';
import '../screens/login/login_screen.dart';
import '../features/profile/presentation/profile_gate.dart';
import '../screens/settings/app_settings_screen.dart';
import '../features/shop/presentation/screens/shop_detail_screen.dart';
import '../features/shop/presentation/screens/shop_landing_screen.dart';
import '../features/shop/presentation/screens/shop_saved_screen.dart';
import '../features/journey/presentation/screens/create_journey_screen.dart';
import '../features/journey/presentation/screens/my_journey_screen.dart';
import '../features/journey/presentation/screens/wallet_rewards_screen.dart';
import '../features/journal/presentation/screens/journal_discover_screen.dart';
import '../features/journal/presentation/screens/journal_search_screen.dart';
import '../features/community/presentation/screens/community_feed_screen.dart';
import '../features/community/presentation/screens/community_discover_screen.dart';
import '../features/community/presentation/screens/community_post_detail_screen.dart';
import '../features/community/presentation/screens/compose/post_select_media_screen.dart';
import '../features/community/presentation/screens/compose/community_select_attachment_screen.dart';
import '../features/community/presentation/screens/compose/community_ask_question_screen.dart';
import '../features/community/presentation/screens/compose/post_compose_publish_screen.dart';
import '../features/community/presentation/screens/profile/community_profile_screen.dart';
import '../features/community/presentation/screens/notifications/community_notifications_screen.dart';
import '../features/community/presentation/screens/saved/community_saved_screen.dart';
import '../features/community/presentation/screens/drafts/community_drafts_screen.dart';
import '../features/community/presentation/screens/qa/community_question_detail_screen.dart';

class AppRoutes {
  // 1. Định nghĩa Constants (Tránh gõ sai string)
  static const String splash = '/';
  static const String login = '/login';
  static const String main = '/main';
  static const String appSettings = '/settings';
  static const String shop = '/shop';
  static const String shopDetail = '/shop/detail';
  static const String shopSaved = '/shop/saved';
  static const String createJourney = '/journey/create';
  static const String myJourney = '/journey/my';
  static const String walletRewards = '/journey/wallet';
  static const String journal = '/journal';
  static const String journalSearch = '/journal/search';
  static const String communityFeed = '/community/feed';
  static const String communityDiscover = '/community/discover';
  static const String communityPost = '/community/post';
  static const String communityCreateMedia = '/community/create/media';
  static const String communityCreateAttachment = '/community/create/attachment';
  static const String communityCreateQuestion = '/community/create/question';
  static const String communityCreatePublish = '/community/create/publish';
  static const String communityProfile = '/community/profile';
  static const String communityNotifications = '/community/notifications';
  static const String communitySaved = '/community/saved';
  static const String communityDrafts = '/community/drafts';
  static const String communityQuestionDetail = '/community/qa/detail';

  // 2. Hàm Generate Route tập trung
  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    bool enableSplashAnimations = true,
  }) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => SplashScreen(
            enableAnimations: enableSplashAnimations,
          ),
        );

      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case main:
        return MaterialPageRoute(builder: (_) => const ProfileGate());

      case appSettings:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AppSettingsScreen(),
        );

      case shop:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ShopLandingScreen(),
        );

      case shopDetail:
        final productId = settings.arguments as String?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ShopDetailScreen(productId: productId),
        );

      case shopSaved:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ShopSavedScreen(),
        );

      case createJourney:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CreateJourneyScreen(),
        );

      case myJourney:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const MyJourneyScreen(),
        );

      case walletRewards:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const WalletRewardsScreen(),
        );

      case journal:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const JournalDiscoverScreen(),
        );

      case journalSearch:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const JournalSearchScreen(),
        );

      case communityFeed:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CommunityFeedScreen(),
        );

      case communityDiscover:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CommunityDiscoverScreen(),
        );

      case communityPost:
        final postId = (settings.arguments as String?) ?? 'post_01_meal';
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CommunityPostDetailScreen(postId: postId),
        );

      case communityCreateMedia:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const PostSelectMediaScreen(),
        );

      case communityCreateAttachment:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CommunitySelectAttachmentScreen(),
        );

      case communityCreateQuestion:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CommunityAskQuestionScreen(),
        );

      case communityCreatePublish:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const PostComposePublishScreen(),
        );

      case communityProfile:
        final authorId = (settings.arguments as String?) ?? 'me';
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CommunityProfileScreen(authorId: authorId),
        );

      case communityNotifications:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CommunityNotificationsScreen(),
        );

      case communitySaved:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CommunitySavedScreen(),
        );

      case communityDrafts:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CommunityDraftsScreen(),
        );

      case communityQuestionDetail:
        final questionId = (settings.arguments as String?) ?? 'post_03_qa';
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CommunityQuestionDetailScreen(questionId: questionId),
        );

      // Mặc định: Trả về trang lỗi hoặc Login nếu không tìm thấy route
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Route not found!')),
          ),
        );
    }
  }
}
