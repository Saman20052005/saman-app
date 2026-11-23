import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/community_call_provider.dart';
import '../screens/dm/community_call_screen.dart';

/// Host listener wrapper that keeps [communityCallProvider] active while the
/// user is inside Saman Community and automatically presents
/// [CommunityCallScreen] on incoming or outgoing calls.
class CommunityCallHostListener extends ConsumerStatefulWidget {
  final Widget child;

  const CommunityCallHostListener({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<CommunityCallHostListener> createState() =>
      _CommunityCallHostListenerState();
}

class _CommunityCallHostListenerState
    extends ConsumerState<CommunityCallHostListener> {
  bool _pushScheduled = false;

  void _pushCallScreenNow() {
    if (!mounted || CommunityCallScreen.isPresented) return;

    final current = ref.read(communityCallProvider);
    final stillRinging =
        current.phase == CallLifecyclePhase.incomingRinging ||
            current.phase == CallLifecyclePhase.outgoingRinging;
    if (!stillRinging) return;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return;

    CommunityCallScreen.isPresented = true;
    navigator.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const CommunityCallScreen(),
      ),
    );
  }

  void _maybePresentCallScreen(CommunityCallState next) {
    final shouldPresent =
        next.phase == CallLifecyclePhase.incomingRinging ||
            next.phase == CallLifecyclePhase.outgoingRinging;
    if (!shouldPresent || CommunityCallScreen.isPresented || _pushScheduled) {
      return;
    }

    final schedulerPhase = SchedulerBinding.instance.schedulerPhase;
    if (schedulerPhase != SchedulerPhase.persistentCallbacks &&
        schedulerPhase != SchedulerPhase.midFrameMicrotasks) {
      _pushCallScreenNow();
      return;
    }

    _pushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushScheduled = false;
      _pushCallScreenNow();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the provider alive while inside Community screens.
    final phase = ref.watch(communityCallProvider.select((s) => s.phase));

    ref.listen<CommunityCallState>(communityCallProvider, (previous, next) {
      _maybePresentCallScreen(next);
    });

    if (phase == CallLifecyclePhase.incomingRinging ||
        phase == CallLifecyclePhase.outgoingRinging) {
      _maybePresentCallScreen(ref.read(communityCallProvider));
    }

    return widget.child;
  }
}
