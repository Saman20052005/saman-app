import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/privacy/data/privacy_service.dart';
import 'package:health_ai_app/features/privacy/presentation/screens/health_consent_screen.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/tokens/saman_home_tokens.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/utils/auth_helper.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/onboarding_flow_screen.dart';

/// Central Routing Gate controlling entry into the application.
///
/// Ensures:
/// - Entry is mediated by verified identity and network-confirmed completeness.
/// - In-flight loading displays a neutral loading screen (Main is not rendered behind).
/// - Network load errors permit retry GET and logout, but do NOT permit onboarding entry.
/// - Unconfirmed/cached complete data does NOT open the gate when remote GET fails.
/// - Incomplete profile directs to the temporary onboarding placeholder (CP3 integration point).
/// - 401 Unauthorized is logged out exactly once, by exactly one owner: the
///   Gate while it has not admitted Main, MainScreen once it has.
/// - Main is retained only for the same confirmed owner AND the same session
///   epoch it was admitted under, so background loads in the same session never
///   unmount it, while a reset or an owner change always revokes entry.
class ProfileGate extends ConsumerStatefulWidget {
  const ProfileGate({super.key});

  /// Test-only escape hatch for legacy entry-point tests that do not mock
  /// `/api/user/consent`. Must remain `false` in production.
  @visibleForTesting
  static bool bypassConsentGateForTests = false;

  @override
  ConsumerState<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends ConsumerState<ProfileGate> {
  /// Owner + session (epoch and notifier instance) Main was admitted under
  /// (null = not admitted). [_entrySerial] makes each admission's key unique.
  String? _enteredOwner;
  int? _enteredEpoch;
  ProfileNotifier? _enteredNotifier;
  int _entrySerial = 0;
  bool _isHandlingUnauthorized = false;

  /// Consent gate state (VN 2026 v1.0-vn-2026) scoped to [_consentCheckedUserId].
  String? _consentCheckedUserId;
  bool _isCheckingConsent = false;
  bool _hasConsented = false;
  String? _consentCheckError;
  int _consentRequestId = 0;

  /// A 401 or user-initiated logout arrived while Main was admitted: MainScreen
  /// performs the logout and the navigation, so it must stay mounted until it
  /// leaves the route stack.
  bool _mainOwnsLogout = false;

  @override
  void initState() {
    super.initState();
    // Listener (not build) so the 401 is seen even when MainScreen's own handler
    // resets the session before this widget rebuilds.
    ref.listenManual<ProfileState>(profileProvider, _onProfileStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profileState = ref.read(profileProvider);
      if (profileState.status == ProfileStatus.initial) {
        ref.read(profileProvider.notifier).loadProfile();
      }
    });
  }

  void _onProfileStateChanged(ProfileState? previous, ProfileState next) {
    final unauthorized = next.isUnauthorized || (previous?.isUnauthorized ?? false);
    if (unauthorized && _enteredOwner != null) {
      _mainOwnsLogout = true;
    }
  }

  bool _isMainRetained(ProfileState state, ProfileNotifier notifier) {
    final owner = _enteredOwner;
    if (owner == null) return false;
    // Epoch AND notifier instance: invalidating the provider builds a new
    // notifier whose epoch restarts at 0, so the epoch alone cannot tell.
    if (_enteredEpoch != notifier.sessionEpoch ||
        !identical(_enteredNotifier, notifier)) {
      return false;
    }
    // Transient states (loading/error) carry no identity: same session keeps Main.
    final current = state.userId;
    const allowGuestMode = kDebugMode ||
        bool.fromEnvironment('ENABLE_GUEST_MODE', defaultValue: false);
    if (allowGuestMode &&
        owner == 'guest_dev_user' &&
        current != null &&
        current.isNotEmpty) {
      return true;
    }
    return current == null || current == owner;
  }

  void _revokeEntry() {
    _enteredOwner = null;
    _enteredEpoch = null;
    _enteredNotifier = null;
    _mainOwnsLogout = false;
    _consentCheckedUserId = null;
    _isCheckingConsent = false;
    _hasConsented = false;
    _consentCheckError = null;
    _consentRequestId++;
  }

  Future<void> _ensureConsentChecked(String userId) async {
    if (!mounted || userId.isEmpty) return;
    if (_consentCheckedUserId == userId &&
        (_isCheckingConsent || _hasConsented || _consentCheckError != null)) {
      return;
    }

    final reqId = ++_consentRequestId;
    setState(() {
      _consentCheckedUserId = userId;
      _isCheckingConsent = true;
      _hasConsented = false;
      _consentCheckError = null;
    });

    try {
      final privacyService = ref.read(privacyServiceProvider);
      final cached = await privacyService.hasCachedConsent(userId);
      if (!mounted || reqId != _consentRequestId) return;
      if (cached) {
        setState(() {
          _hasConsented = true;
          _isCheckingConsent = false;
          _consentCheckError = null;
        });
        return;
      }

      final status = await privacyService.fetchConsentStatus(userId: userId);
      if (!mounted || reqId != _consentRequestId) return;
      setState(() {
        _hasConsented = status.hasConsented;
        _isCheckingConsent = false;
        _consentCheckError = null;
      });
    } catch (e) {
      if (!mounted || reqId != _consentRequestId) return;
      setState(() {
        _isCheckingConsent = false;
        _consentCheckError =
            'Không thể kiểm tra trạng thái đồng ý dữ liệu sức khỏe.';
      });
    }
  }

  Future<void> _handleUnauthorized() async {
    if (_isHandlingUnauthorized || !mounted) return;
    _isHandlingUnauthorized = true;

    try {
      await AuthHelper.logout(ref);
      if (mounted) {
        _revokeEntry();
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.login,
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('[PROFILE_GATE] Error in logout: $e');
      _isHandlingUnauthorized = false;
      if (mounted) {
        if (e is LogoutException &&
            (e.tokenState == AuthTokenState.confirmedLost ||
             e.tokenState == AuthTokenState.indeterminate)) {
          _revokeEntry();
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đăng xuất thất bại: $e'),
              backgroundColor: const Color(0xFFEF4444),
              action: SnackBarAction(
                label: 'Thử lại',
                textColor: Colors.white,
                onPressed: _handleUnauthorized,
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);
    final isLoggingOut = ref.watch(authLoggingOutProvider);

    // MainScreen is mid-logout after a 401 or while a user logout is executing:
    // leave it mounted until navigation removes this route.
    // Stable IgnorePointer wrapper is used across all states; only ignoring changes.
    if (_mainOwnsLogout || (isLoggingOut && _enteredOwner != null)) {
      return _buildMain(ignoring: isLoggingOut);
    }

    // Entry granted earlier is revoked by a reset/invalidation (epoch or
    // notifier instance) or by an owner change.
    final retained = _isMainRetained(profileState, notifier);
    if (!retained && _enteredOwner != null) _revokeEntry();

    // 1. Unauthorized session -> logout once, by a single owner.
    if (profileState.isUnauthorized) {
      // Once admitted, MainScreen owns the 401 (logout + navigation).
      if (retained) return _buildMain(ignoring: isLoggingOut);
      if (!isLoggingOut) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleUnauthorized();
        });
      }
      return const _GateLoadingView();
    }

    // 2. Same owner and same session: background/edit loads must NOT tear
    // down MainScreen or reset active forms.
    if (retained) return _buildMain(ignoring: isLoggingOut);

    // 3. Complete and network-confirmed -> check VN 2026 Consent Gate before admitting Main.
    if (profileState.isCompleteAndConfirmed) {
      final userId = profileState.userId ?? '';
      final shouldBypassConsent = ProfileGate.bypassConsentGateForTests ||
          userId.isEmpty ||
          userId == 'guest_dev_user';

      if (!shouldBypassConsent) {
        if (_consentCheckedUserId != userId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureConsentChecked(userId);
          });
          return const _GateLoadingView();
        }
        if (_isCheckingConsent) {
          return const _GateLoadingView();
        }
        if (_consentCheckError != null) {
          return _GateErrorView(
            onRetry: () {
              setState(() {
                _consentCheckedUserId = null;
                _consentCheckError = null;
              });
              _ensureConsentChecked(userId);
            },
            onLogout: _handleUnauthorized,
          );
        }
        if (!_hasConsented) {
          return HealthConsentScreen(
            key: ValueKey('health_consent_$userId'),
            userId: userId,
            onAccepted: () {
              if (!mounted) return;
              setState(() {
                _hasConsented = true;
                _isCheckingConsent = false;
                _consentCheckError = null;
              });
            },
          );
        }
      }

      _enteredOwner = profileState.userId;
      _enteredEpoch = notifier.sessionEpoch;
      _enteredNotifier = notifier;
      _entrySerial++;
      return _buildMain(ignoring: isLoggingOut);
    }

    // 4. Incomplete and network-confirmed -> Onboarding Flow (CP3)
    if (profileState.isIncompleteAndConfirmed) {
      return OnboardingFlowScreen(
        key: ValueKey(
            'onboarding_flow_${profileState.userId}_${notifier.sessionEpoch}'),
        onLogout: _handleUnauthorized,
      );
    }

    // 5. In-flight loading or initial state -> Neutral Loading Screen
    if (profileState.isLoading || profileState.status == ProfileStatus.initial) {
      return const _GateLoadingView();
    }

    // 6. Load Error or unconfirmed offline cache -> Load Error View (permits retry GET and logout)
    return _GateErrorView(
      onRetry: () => ref.read(profileProvider.notifier).loadProfile(),
      onLogout: _handleUnauthorized,
    );
  }

  Widget _buildMain({bool ignoring = false}) {
    return IgnorePointer(
      ignoring: ignoring,
      child: MainScreen(
        key: ValueKey('profile_gate_main_${_enteredOwner}_$_entrySerial'),
        loadProfileOnInit: false,
      ),
    );
  }
}

class _GateLoadingView extends StatelessWidget {
  const _GateLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: Key('profile_gate_loading_view'),
      backgroundColor: SamanHomeTokens.canvas,
      body: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor:
                AlwaysStoppedAnimation<Color>(SamanHomeTokens.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _GateErrorView extends StatelessWidget {
  const _GateErrorView({required this.onRetry, required this.onLogout});

  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('profile_gate_error_view'),
      backgroundColor: SamanHomeTokens.canvas,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 56,
                  color: SamanHomeTokens.textSecondary,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Không thể tải hồ sơ sức khỏe',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: SamanHomeTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Không thể kết nối để tải hồ sơ của bạn. Vui lòng kiểm tra kết nối mạng và thử lại.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: SamanHomeTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  key: const Key('profile_gate_retry_button'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Thử lại'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SamanHomeTokens.actionButtonSurface,
                    foregroundColor: SamanHomeTokens.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(SamanHomeTokens.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  key: const Key('profile_gate_error_logout_button'),
                  onPressed: onLogout,
                  child: const Text(
                    'Đăng xuất',
                    style: TextStyle(color: SamanHomeTokens.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
