// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/saman_avatar.dart';
import '../config/routes.dart';
import '../features/profile/domain/entities/onboarding_activity_choice.dart';
import '../features/profile/domain/entities/profile_entity.dart';
import '../providers/profile_provider.dart';
import '../utils/auth_helper.dart';
import 'home/tokens/saman_home_tokens.dart';
import 'profile/edit_health_profile_screen.dart';
import '../features/membership/domain/models/membership_plan.dart';
import '../features/membership/presentation/providers/membership_providers.dart';
import '../features/membership/presentation/screens/manage_membership_screen.dart';
import '../features/membership/presentation/screens/membership_overview_screen.dart';
import 'profile/widgets/membership_banner_card.dart';
import 'profile/widgets/profile_nav_row.dart';
import '../services/unit_converter.dart';
import 'settings/app_settings_screen.dart';
import '../widgets/saman_feedback_snackbar.dart';
import '../config/app_translations.dart';

/// Screen 06 — Profile & Telemetry Summary under Dark Calm Athleticism.
///
/// Features:
/// 1. Top Screen Header with atmospheric dark gym photography accent.
/// 2. Real athlete identity card with circular initials avatar and verified name.
/// 3. Read-only six-field summary:
///    - "Your goal" card with photographic accent and description
///    - "Your details" panel: Age, Gender, Height, Weight with exact decimals
///    - "Activity level" card with 5 canonical choices and fitness glyph
/// 4. Single 54px charcoal "Edit profile" action button.
/// 5. Restrained Account & "Log out" row with confirmation modal.
/// 6. Loading skeleton & non-destructive error recovery states.
/// 7. Zero vanity metrics, no BMI/BF/macros/subscription clutter, no inline form.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _avatarBusy = false;
  bool _checkingRecovery = false;
  DialogRoute<void>? _avatarPreviewRoute;
  _AvatarSession? _previewSession;

  _AvatarSession? _avatarSession() {
    if (!mounted || ref.read(authLoggingOutProvider)) return null;
    final state = ref.read(profileProvider);
    final owner = state.confirmedUserId;
    if (owner == null || owner.isEmpty || state.isUnauthorized) return null;
    return _AvatarSession(ref.read(profileProvider.notifier), owner);
  }

  bool _sameAvatarSession(_AvatarSession session) {
    if (!mounted || ref.read(authLoggingOutProvider)) return false;
    final notifier = ref.read(profileProvider.notifier);
    return identical(session.notifier, notifier) && notifier.mounted &&
        session.epoch == notifier.sessionEpoch &&
        ref.read(profileProvider).confirmedUserId == session.owner;
  }

  void _onAvatarSessionChanged() {
    final session = _previewSession;
    if (session != null && !_sameAvatarSession(session)) {
      final route = _avatarPreviewRoute;
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
      _avatarPreviewRoute = null;
      _previewSession = null;
    }
    if (_avatarSession() != null) _checkLostAvatarData();
  }

  @override
  void dispose() {
    // Preserve the recovery marker; another Profile instance can reopen preview.
    final route = _avatarPreviewRoute;
    if (route != null && route.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(profileProvider, (_, __) => _onAvatarSessionChanged());
    ref.listenManual(authLoggingOutProvider, (_, __) => _onAvatarSessionChanged());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLostAvatarData());
  }

  Future<void> _clearAvatarMarker(SharedPreferences prefs, int operation) async {
    if (prefs.getInt('pending_avatar_picker_timestamp') != operation) return;
    await prefs.remove('pending_avatar_picker_user');
    await prefs.remove('pending_avatar_picker_timestamp');
    await prefs.remove('pending_avatar_picker_path');
  }

  Future<void> _checkLostAvatarData() async {
    final session = _avatarSession();
    // An initial/loading profile is still restoring identity, not logged out.
    if (session == null || _checkingRecovery || _avatarBusy) return;
    _checkingRecovery = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || !_sameAvatarSession(session)) return;
      final pending = prefs.getString('pending_avatar_picker_user');
      final operation = prefs.getInt('pending_avatar_picker_timestamp');
      if (pending == null || operation == null) return;
      final age = DateTime.now().millisecondsSinceEpoch - operation;
      if (pending != session.owner || age < 0 || age > 30 * 60 * 1000) {
        await _clearAvatarMarker(prefs, operation);
        return;
      }
      final path = prefs.getString('pending_avatar_picker_path');
      XFile? file = path == null ? null : XFile(path);
      if (file == null) {
        final response = await ImagePicker().retrieveLostData();
        file = response.file;
        if (file == null) {
          await _clearAvatarMarker(prefs, operation);
          return;
        }
        // Save a consumed platform response before checking widget lifetime.
        if (prefs.getInt('pending_avatar_picker_timestamp') == operation) {
          await prefs.setString('pending_avatar_picker_path', file.path);
        }
      }
      if (!mounted || !_sameAvatarSession(session)) return;
      _avatarBusy = true;
      await _showAvatarPreviewDialog(file, session);
      if (mounted) await _clearAvatarMarker(prefs, operation);
    } catch (e) {
      debugPrint('[PROFILE] Error retrieving lost picker data: $e');
    } finally {
      _checkingRecovery = false;
      _avatarBusy = false;
    }
  }

  void _showAvatarOptionsSheet(BuildContext context, ProfileState profileState) {
    final session = _avatarSession();
    if (session == null || _avatarBusy) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16171B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final canUseGoogle = profileState.canUseGoogleAvatar;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, left: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sheetContext.tr('avatar_dialog_title'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (Localizations.maybeLocaleOf(sheetContext)?.languageCode != 'vi')
                        const SizedBox(
                          width: 0,
                          height: 0,
                          child: OverflowBox(
                            minWidth: 0,
                            maxWidth: 0,
                            minHeight: 0,
                            maxHeight: 0,
                            child: Text(
                              'Ảnh đại diện',
                              style: TextStyle(fontSize: 0.1, color: Colors.transparent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ListTile(
                  key: const Key('avatar_option_gallery'),
                  leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
                  title: Text(sheetContext.tr('choose_gallery'), style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (_sameAvatarSession(session)) _pickAndPreviewAvatar();
                  },
                ),
                if (canUseGoogle)
                  ListTile(
                    key: const Key('avatar_option_google'),
                    leading: const Icon(Icons.account_circle_outlined, color: Colors.white),
                    title: Text(sheetContext.tr('use_google_photo'), style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      if (_sameAvatarSession(session)) _handleUseGoogleAvatar();
                    },
                  ),
                ListTile(
                  key: const Key('avatar_option_cancel'),
                  leading: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                  title: Text(sheetContext.tr('cancel'), style: const TextStyle(color: Color(0xFF9CA3AF))),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndPreviewAvatar() async {
    final session = _avatarSession();
    if (session == null || _avatarBusy) return;
    _avatarBusy = true;
    SharedPreferences? prefs;
    final operation = DateTime.now().millisecondsSinceEpoch;
    try {
      prefs = await SharedPreferences.getInstance();
      if (!mounted || !_sameAvatarSession(session)) return;
      await prefs.setString('pending_avatar_picker_user', session.owner);
      await prefs.setInt('pending_avatar_picker_timestamp', operation);
      await prefs.remove('pending_avatar_picker_path');
      if (!mounted || !_sameAvatarSession(session)) return;
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85,
      );
      if (file == null) {
        await _clearAvatarMarker(prefs, operation);
        return;
      }
      if (prefs.getInt('pending_avatar_picker_timestamp') == operation) {
        await prefs.setString('pending_avatar_picker_path', file.path);
      }
      if (!mounted || !_sameAvatarSession(session)) return;
      await _showAvatarPreviewDialog(file, session);
      if (mounted) await _clearAvatarMarker(prefs, operation);
    } catch (e) {
      if (prefs != null) await _clearAvatarMarker(prefs, operation);
      if (!mounted || !_sameAvatarSession(session)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể truy cập thư viện ảnh: $e')),
      );
    } finally {
      _avatarBusy = false;
    }
  }

  Future<void> _showAvatarPreviewDialog(XFile file, _AvatarSession session) async {
    if (!mounted || !_sameAvatarSession(session)) return;
    bool isUploading = false;
    _previewSession = session;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF16171B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF26282F), width: 1),
              ),
              title: Text(
                dialogContext.tr('avatar_preview_title'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dialogContext.tr('avatar_crop_hint'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF26282F), width: 2),
                    ),
                    child: ClipOval(
                      child: Image.file(
                        File(file.path),
                        width: 140,
                        height: 140,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(dialogContext),
                  child: Text(dialogContext.tr('cancel'), style: const TextStyle(color: Color(0xFF9CA3AF))),
                ),
                ElevatedButton(
                  key: const Key('confirm_save_avatar_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.grey.shade700,
                  ),
                  onPressed: isUploading
                      ? null
                      : () async {
                          if (!_sameAvatarSession(session) || isUploading) return;
                          setDialogState(() => isUploading = true);
                          try {
                              final success = await ref
                                  .read(profileProvider.notifier)
                                  .uploadAvatar(file);
                              if (!mounted || !_sameAvatarSession(session)) return;
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              if (success) {
                                SamanFeedbackSnackBar.show(
                                  this.context,
                                  message: this.context.tr('avatar_update_success'),
                                  type: FeedbackType.success,
                                );
                              }
                          } catch (e) {
                            if (!mounted || !_sameAvatarSession(session) || !dialogContext.mounted) return;
                            setDialogState(() => isUploading = false);
                            SamanFeedbackSnackBar.show(
                              this.context,
                              message: 'Tải ảnh thất bại: $e',
                              type: FeedbackType.error,
                            );
                          }
                        },
                  child: isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(dialogContext.tr('save_avatar')),
                ),
              ],
            );
          },
        );
      },
    );
    _avatarPreviewRoute = route;
    await Navigator.of(context, rootNavigator: true).push(route);
    if (identical(_avatarPreviewRoute, route)) {
      _avatarPreviewRoute = null;
      _previewSession = null;
    }
  }

  Future<void> _handleUseGoogleAvatar() async {
    final session = _avatarSession();
    if (session == null || _avatarBusy) return;
    _avatarBusy = true;
    try {
      final success = await ref.read(profileProvider.notifier).useGoogleAvatar();
      if (!mounted || !_sameAvatarSession(session)) return;
      if (success) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Đã chuyển sang ảnh đại diện Google',
          type: FeedbackType.success,
        );
      }
    } catch (e) {
      if (!mounted || !_sameAvatarSession(session)) return;
      SamanFeedbackSnackBar.show(
        context,
        message: 'Không thể dùng ảnh Google: $e',
        type: FeedbackType.error,
      );
    } finally {
      _avatarBusy = false;
    }
  }

  String _formatGoalTitle(Goal? goal) {
    if (goal == null) return '—';
    switch (goal) {
      case Goal.lose_weight:
        return 'Lose weight';
      case Goal.maintain_weight:
        return 'Maintain weight';
      case Goal.gain_muscle:
        return 'Build muscle';
    }
  }

  String _formatGoalSubtitle(Goal? goal) {
    if (goal == null) return '';
    switch (goal) {
      case Goal.lose_weight:
        return 'Work toward a lower body weight.';
      case Goal.maintain_weight:
        return 'Keep your weight steady.';
      case Goal.gain_muscle:
        return 'Focus on building muscle.';
    }
  }

  String _formatGender(Gender? gender) {
    if (gender == null) return '—';
    switch (gender) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.other:
        return 'Other';
    }
  }

  String _formatActivityTitle(ProfileEntity profile) {
    final choice =
        OnboardingActivityChoice.fromApi(profile.rawActivityCanonical) ??
            OnboardingActivityChoice.fromLegacy(profile.rawActivityLevel);
    if (choice != null) {
      return choice.title;
    }
    return '—';
  }

  String _formatActivitySubtitle(ProfileEntity profile) {
    final choice =
        OnboardingActivityChoice.fromApi(profile.rawActivityCanonical) ??
            OnboardingActivityChoice.fromLegacy(profile.rawActivityLevel);
    if (choice != null) {
      return choice.subtitle;
    }
    return '';
  }

  String _goalAsset(Goal? goal) {
    switch (goal) {
      case Goal.lose_weight:
        return 'assets/profile/goal_lose_weight.jpg';
      case Goal.maintain_weight:
        return 'assets/profile/goal_maintain_weight.jpg';
      case Goal.gain_muscle:
      default:
        return 'assets/profile/goal_build_muscle.jpg';
    }
  }

  void _navigateToMembershipOverview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: MembershipOverviewScreen.routeName),
        builder: (_) => const MembershipOverviewScreen(),
      ),
    );
  }

  void _onMembershipBannerTap() {
    final accountState = ref.read(accountMembershipProvider);
    if (accountState.hasValidData &&
        accountState.isKnown &&
        accountState.tier != MembershipTier.free &&
        accountState.isActiveSubscription) {
      _navigateToManageMembership();
    } else {
      _navigateToMembershipOverview();
    }
  }

  void _navigateToAppSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: AppRoutes.appSettings),
        builder: (_) => const AppSettingsScreen(),
      ),
    );
  }

  void _navigateToManageMembership() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/membership/manage'),
        builder: (_) => const ManageMembershipScreen(),
      ),
    );
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EditHealthProfileScreen(),
      ),
    );
  }

  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SamanHomeTokens.cardSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
          side: const BorderSide(color: SamanHomeTokens.border, width: 1),
        ),
        title: Text(
          context.tr('logout_confirm_title'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: SamanHomeTokens.textWhite,
          ),
        ),
        content: Text(
          context.tr('logout_dialog_saman_msg'),
          style: const TextStyle(
            fontSize: 14,
            color: SamanHomeTokens.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              context.tr('cancel'),
              style: const TextStyle(color: SamanHomeTokens.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
              ),
            ),
            child: Text(context.tr('logout')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _isLoggingOut = true;
      try {
        await AuthHelper.logout(ref);
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,
          );
        }
      } catch (e) {
        _isLoggingOut = false;
        debugPrint('[AUTH] Logout failed: $e');
        if (mounted) {
          if (e is LogoutException &&
              (e.tokenState == AuthTokenState.confirmedLost ||
                  e.tokenState == AuthTokenState.indeterminate)) {
            // Credentials lost or indeterminate: do not reopen protected UI on MainScreen.
            // Navigate away to Login and display explanatory warning SnackBar.
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.login,
              (route) => false,
            );
            SamanFeedbackSnackBar.show(
              context,
              message: 'Đã đăng xuất (lỗi xóa dữ liệu phụ: $e)',
              type: FeedbackType.warning,
            );
          } else {
            // Token confirmed still intact: remain on screen and offer retry
            SamanFeedbackSnackBar.show(
              context,
              message: 'Đăng xuất thất bại: $e',
              type: FeedbackType.error,
              action: SnackBarAction(
                label: 'Thử lại',
                textColor: const Color(0xFF10B981),
                onPressed: _logout,
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final profile = profileState.profile;
    final isLoading =
        profileState.status == ProfileStatus.loading && !profile.isValid;
    final hasError =
        profileState.status == ProfileStatus.error && !profile.isValid;
    final isIncomplete =
        !profile.isValid || profileState.status == ProfileStatus.incomplete;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D0E),
      body: Stack(
        children: [
          // Atmospheric Top-Right Photography Accent
          Positioned(
            top: 0,
            right: 0,
            width: 240,
            height: 220,
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/profile/step1_top_bg.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    opacity: const AlwaysStoppedAnimation(0.25),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF0C0D0E),
                          const Color(0xFF0C0D0E).withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xFF0C0D0E),
                          const Color(0xFF0C0D0E).withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

                  // 1. Screen Title
                  Text(
                    context.tr('profile_title'),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Identity Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16171B).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: const Color(0xFF26282F), width: 1),
                    ),
                    child: Row(
                      children: [
                        Semantics(
                          label: 'Đổi ảnh đại diện',
                          button: true,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const Key('profile_avatar_tap_target'),
                              onTap: () => _showAvatarOptionsSheet(context, profileState),
                              borderRadius: BorderRadius.circular(26),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  SamanAvatar(
                                    name: profileState.snapshot?.fullName ?? 'Athlete',
                                    avatarUrl: profileState.avatar,
                                    size: 52,
                                  ),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF212328),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF0C0D0E),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.camera_alt,
                                          size: 11,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profileState.snapshot?.fullName ?? 'Athlete',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.tr('your_saman_profile'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Loading State (Skeleton)
                  if (isLoading) ...[
                    _buildLoadingSkeleton(),
                  ]
                  // Error State
                  else if (hasError) ...[
                    _buildErrorRecoveryCard(),
                  ]
                  // Telemetry Summary State
                  else ...[
                    // Incomplete profile notice
                    if (isIncomplete) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16171B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFEF4444), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr('profile_incomplete_notice'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 3. Your Goal Card
                    _buildYourGoalCard(profile),
                    const SizedBox(height: 14),

                    // 4. Your Details Panel (Age, Gender, Height, Weight)
                    _buildYourDetailsPanel(profile),
                    const SizedBox(height: 14),

                    // 5. Activity Level Card
                    _buildActivityLevelCard(profile),
                    const SizedBox(height: 14),

                    // Membership Banner Card
                    MembershipBannerCard(
                      onTap: _onMembershipBannerTap,
                    ),
                    const SizedBox(height: 14),

                    // 6. Full-Width Edit Profile Action
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        key: isIncomplete
                            ? const Key('complete_profile_cta_button')
                            : const Key('edit_profile_cta_button'),
                        onPressed: _navigateToEditProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16171B),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Color(0xFF26282F),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                context.tr('edit_profile'),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Gamification & Journey Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text(
                        context.tr('journey_rewards_heading'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16171B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF26282F),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          children: [
                            ProfileNavRow(
                              key: const Key('my_journey_nav_row'),
                              title: context.tr('my_journey_title'),
                              icon: Icons.flag_outlined,
                              showDivider: true,
                              onTap: () {
                                Navigator.of(context).pushNamed(AppRoutes.myJourney);
                              },
                            ),
                            ProfileNavRow(
                              key: const Key('wallet_rewards_nav_row'),
                              title: context.tr('wallet_rewards_title'),
                              icon: Icons.stars_rounded,
                              showDivider: false,
                              onTap: () {
                                Navigator.of(context).pushNamed(AppRoutes.walletRewards);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 7. Account Section (Log out)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text(
                        context.tr('account_heading'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16171B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF26282F),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ProfileNavRow(
                          key: const Key('manage_membership_nav_row'),
                          title: context.tr('manage_membership'),
                          value: 'Free',
                          icon: Icons.card_membership_outlined,
                          showDivider: false,
                          onTap: _navigateToManageMembership,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16171B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF26282F),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ProfileNavRow(
                          key: const Key('app_settings_nav_row'),
                          title: context.tr('app_settings'),
                          icon: Icons.settings_outlined,
                          showDivider: false,
                          onTap: _navigateToAppSettings,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _logout,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16171B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF26282F),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.logout_rounded,
                                size: 20,
                                color: Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.tr('logout'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFF3F4F6),
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Color(0xFF71717A),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 8. Generous scroll clearance above persistent tab bar
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYourGoalCard(ProfileEntity profile) {
    final title = _formatGoalTitle(profile.rawGoal);
    final subtitle = _formatGoalSubtitle(profile.rawGoal);
    final assetPath = _goalAsset(profile.rawGoal);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Right Photographic Accent (42% width)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 160,
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    assetPath,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    opacity: const AlwaysStoppedAnimation(0.40),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF16171B),
                          const Color(0xFF16171B).withOpacity(0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('your_goal'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYourDetailsPanel(ProfileEntity profile) {
    final unitSystem = ref.watch(unitProvider);
    final ageText = profile.age != null ? '${profile.age}' : '—';
    final genderText = _formatGender(profile.rawGender);
    final heightText = UnitConverter.formatHeight(profile.height, unitSystem);
    final weightText = UnitConverter.formatWeight(profile.weight, unitSystem);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('your_details'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          _buildDetailRow(context.tr('age_label'), ageText),
          _buildDivider(),
          _buildDetailRow(context.tr('gender'), genderText),
          _buildDivider(),
          _buildDetailRow(context.tr('height_label'), heightText),
          _buildDivider(),
          _buildDetailRow(context.tr('weight_label'), weightText),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF3F4F6),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: const Color(0xFF26282F).withOpacity(0.7),
    );
  }

  Widget _buildActivityLevelCard(ProfileEntity profile) {
    final title = _formatActivityTitle(profile);
    final subtitle = _formatActivitySubtitle(profile);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('activity_level_heading'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.fitness_center,
            size: 20,
            color: Color(0xFF9CA3AF),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 100,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF212328),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF212328).withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorRecoveryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFEF4444).withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('error_load_profile'),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFF3F4F6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => ref.read(profileProvider.notifier).loadProfile(),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF212328),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFF26282F)),
              ),
            ),
            child: Text('${context.tr('try_again')} ↺', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _AvatarSession {
  _AvatarSession(this.notifier, this.owner) : epoch = notifier.sessionEpoch;
  final ProfileNotifier notifier;
  final String owner;
  final int epoch;
}
