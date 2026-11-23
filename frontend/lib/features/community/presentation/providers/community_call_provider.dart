import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_call_manager.dart';
import 'community_dm_provider.dart';

export 'community_call_manager.dart';

final communityRtcBridgeFactoryProvider =
    Provider<CommunityRtcBridgeFactory>((ref) {
  return FlutterWebRtcBridge.new;
});

final communityCallPermissionCheckerProvider =
    Provider<CallPermissionChecker>((ref) {
  return defaultCallPermissionChecker;
});

final communityCallProvider =
    StateNotifierProvider<CommunityCallNotifier, CommunityCallState>((ref) {
  final wsService = ref.watch(communityDmWsServiceProvider);
  final bridgeFactory = ref.watch(communityRtcBridgeFactoryProvider);
  final permissionChecker = ref.watch(communityCallPermissionCheckerProvider);
  return CommunityCallNotifier(
    wsService: wsService,
    rtcBridgeFactory: bridgeFactory,
    permissionChecker: permissionChecker,
  );
});
