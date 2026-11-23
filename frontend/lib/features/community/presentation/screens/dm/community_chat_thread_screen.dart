import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../../../config/app_translations.dart';
import '../../../../../config/routes.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../data/datasources/community_dm_ws_service.dart';
import '../../../domain/models/community_dm.dart';
import '../../providers/community_call_provider.dart';
import '../../providers/community_dm_provider.dart';
import '../../providers/community_providers.dart';
import '../../tokens/saman_ig_tokens.dart';
import '../../widgets/community_call_host_listener.dart';
import '../../widgets/dm_media_viewer.dart';
import '../../widgets/dm_voice_bubble.dart';
import 'community_call_screen.dart';

/// R17 Messenger-Lite 1-on-1 real-time chat thread screen.
/// Supports text, voice notes (record + playback), photos, videos,
/// shared post previews, story replies, typing indicators, read receipts,
/// and message recall/deletion.
class CommunityChatThreadScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final DmParticipant peer;
  final DmConversation? initialConversation;

  const CommunityChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.peer,
    this.initialConversation,
  });

  @override
  ConsumerState<CommunityChatThreadScreen> createState() =>
      _CommunityChatThreadScreenState();
}

class _CommunityChatThreadScreenState
    extends ConsumerState<CommunityChatThreadScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();

  CommunityDmWsService? _wsService;
  Timer? _typingDebounceTimer;
  Timer? _recordingTimer;

  bool _hasText = false;
  bool _isTypingSent = false;
  bool _isRecording = false;
  bool _isUploadingMedia = false;
  int _recordingSeconds = 0;
  DateTime? _recordingStartedAt;
  String? _activeRecordingPath;
  String? _revealedTimeMessageId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _wsService = ref.read(communityDmWsServiceProvider);
      _wsService?.connect();
      final notifier =
          ref.read(communityChatThreadProvider(widget.conversationId).notifier);
      notifier.loadMessages();
      notifier.markRead();
    });
  }

  @override
  void dispose() {
    _typingDebounceTimer?.cancel();
    _recordingTimer?.cancel();
    if (_isTypingSent) {
      _wsService?.sendTyping(widget.conversationId, false);
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    _inputFocusNode.dispose();
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      final state = ref.read(communityChatThreadProvider(widget.conversationId));
      if (state.nextCursor != null && !state.isLoadingMore && !state.isLoading) {
        ref
            .read(communityChatThreadProvider(widget.conversationId).notifier)
            .loadMessages(loadMore: true);
      }
    }
  }

  void _handleTextChanged(String value) {
    final trimmedNotEmpty = value.trim().isNotEmpty;
    if (trimmedNotEmpty != _hasText) {
      setState(() {
        _hasText = trimmedNotEmpty;
      });
    }

    final notifier =
        ref.read(communityChatThreadProvider(widget.conversationId).notifier);
    if (!trimmedNotEmpty) {
      _stopTypingSignal(notifier);
      return;
    }

    if (!_isTypingSent) {
      _isTypingSent = true;
      notifier.sendTyping(true);
    }
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _stopTypingSignal(notifier);
    });
  }

  void _stopTypingSignal(CommunityChatThreadNotifier notifier) {
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = null;
    if (_isTypingSent) {
      _isTypingSent = false;
      notifier.sendTyping(false);
    }
  }

  Future<void> _sendTextMessage() async {
    final content = _textController.text.trim();
    if (content.isEmpty) return;

    final notifier =
        ref.read(communityChatThreadProvider(widget.conversationId).notifier);
    _textController.clear();
    if (mounted) {
      setState(() {
        _hasText = false;
      });
    }
    _stopTypingSignal(notifier);

    await notifier.sendMessage(
      type: DmMessageType.text,
      content: content,
    );
  }

  Future<void> _showMediaPickerSheet() async {
    if (_isUploadingMedia || _isRecording) return;
    _inputFocusNode.unfocus();
    final ig = SamanIgTokens.of(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ig.textMuted.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Đính kèm đa phương tiện',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFamily: SamanIgTokens.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ig.textPrimary,
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                _MediaPickerOptionTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Chọn ảnh',
                  subtitle: 'Gửi hình ảnh từ thư viện thiết bị',
                  ig: ig,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndSendImage();
                  },
                ),
                const SizedBox(height: 8),
                _MediaPickerOptionTile(
                  icon: Icons.video_library_outlined,
                  title: 'Chọn video',
                  subtitle: 'Gửi video từ thư viện thiết bị',
                  ig: ig,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndSendVideo(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 8),
                _MediaPickerOptionTile(
                  icon: Icons.videocam_outlined,
                  title: 'Quay video',
                  subtitle: 'Quay trực tiếp bằng camera (tối đa 60 giây)',
                  ig: ig,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndSendVideo(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      setState(() {
        _isUploadingMedia = true;
      });

      final bytes = await picked.readAsBytes();
      final mimeType = _detectImageMimeType(picked.name);
      final filename = picked.name.isNotEmpty
          ? picked.name
          : 'dm_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final repo = ref.read(communityRepositoryProvider);
      final uploaded = await repo.uploadDmMedia(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      if (!mounted) return;

      await ref
          .read(communityChatThreadProvider(widget.conversationId).notifier)
          .sendMessage(
            type: DmMessageType.photo,
            mediaUrl: uploaded.mediaUrl,
          );
    } catch (_) {
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể gửi hình ảnh. Vui lòng thử lại.',
          type: FeedbackType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    }
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (picked == null || !mounted) return;

      setState(() {
        _isUploadingMedia = true;
      });

      final bytes = await picked.readAsBytes();
      final mimeType = _detectVideoMimeType(picked.name);
      final filename = picked.name.isNotEmpty
          ? picked.name
          : 'dm_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final repo = ref.read(communityRepositoryProvider);
      final uploaded = await repo.uploadDmMedia(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      if (!mounted) return;

      await ref
          .read(communityChatThreadProvider(widget.conversationId).notifier)
          .sendMessage(
            type: DmMessageType.video,
            mediaUrl: uploaded.mediaUrl,
          );
    } catch (_) {
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể gửi video. Vui lòng thử lại.',
          type: FeedbackType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    }
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecording || _isUploadingMedia) return;

    try {
      final permission = await Permission.microphone.request();
      if (!mounted) return;
      if (!permission.isGranted) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Vui lòng cấp quyền micro để ghi âm tin nhắn thoại.',
          type: FeedbackType.warning,
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}${Platform.pathSeparator}dm_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      if (!mounted) {
        await _audioRecorder.cancel();
        return;
      }

      _activeRecordingPath = filePath;
      _recordingStartedAt = DateTime.now();
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecording) return;
        final started = _recordingStartedAt;
        final elapsed =
            started != null ? DateTime.now().difference(started).inSeconds : 0;
        setState(() {
          _recordingSeconds = elapsed;
        });
      });

      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
    } catch (_) {
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể bắt đầu ghi âm.',
          type: FeedbackType.error,
        );
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final pathToDelete = _activeRecordingPath;
    _activeRecordingPath = null;
    _recordingStartedAt = null;

    try {
      await _audioRecorder.cancel();
    } catch (_) {}

    if (pathToDelete != null) {
      _deleteTempFileSilently(pathToDelete);
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
    });
  }

  Future<void> _stopAndSendVoiceRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;
    final startedAt = _recordingStartedAt;
    _recordingStartedAt = null;

    final elapsedSeconds = startedAt != null
        ? DateTime.now().difference(startedAt).inMilliseconds / 1000.0
        : _recordingSeconds.toDouble();
    final durationSeconds = elapsedSeconds < 0.5 ? 1.0 : elapsedSeconds;

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
        _isUploadingMedia = true;
      });
    }

    String? recordedPath;
    try {
      recordedPath = await _audioRecorder.stop() ?? _activeRecordingPath;
      _activeRecordingPath = null;
      if (recordedPath == null || recordedPath.isEmpty) {
        throw StateError('No audio file produced');
      }

      final file = File(recordedPath);
      if (!await file.exists()) {
        throw StateError('Recorded audio file does not exist');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('Recorded audio file is empty');
      }

      final filename =
          'dm_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final uploaded = await ref.read(communityRepositoryProvider).uploadDmMedia(
            bytes: bytes,
            filename: filename,
            mimeType: 'audio/mp4',
          );
      if (!mounted) return;

      await ref
          .read(communityChatThreadProvider(widget.conversationId).notifier)
          .sendMessage(
            type: DmMessageType.voice,
            mediaUrl: uploaded.mediaUrl,
            durationSeconds: double.parse(durationSeconds.toStringAsFixed(1)),
          );
    } catch (_) {
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể gửi tin nhắn thoại.',
          type: FeedbackType.error,
        );
      }
    } finally {
      if (recordedPath != null) {
        _deleteTempFileSilently(recordedPath);
      }
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    }
  }

  void _deleteTempFileSilently(String path) {
    unawaited(() async {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }());
  }

  Future<void> _confirmDeleteMessage(DmMessage message) async {
    final ig = SamanIgTokens.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogTextTheme = Theme.of(dialogContext).textTheme;
        return AlertDialog(
          backgroundColor: ig.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: ig.border),
          ),
          title: Text(
            'Thu hồi tin nhắn?',
            style: dialogTextTheme.titleMedium?.copyWith(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: ig.textPrimary,
            ),
          ),
          content: Text(
            'Tin nhắn này sẽ bị thu hồi cho cả hai phía trong cuộc trò chuyện.',
            style: dialogTextTheme.bodyMedium?.copyWith(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 14,
              color: ig.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
              ),
              child: Text(
                'Hủy',
                style: dialogTextTheme.labelLarge?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  color: ig.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
              ),
              child: Text(
                'Thu hồi',
                style: dialogTextTheme.labelLarge?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  color: ig.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    try {
      final ok = await ref
          .read(communityChatThreadProvider(widget.conversationId).notifier)
          .deleteMessage(message.id);
      if (!mounted) return;
      if (!ok) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể thu hồi tin nhắn.',
          type: FeedbackType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể thu hồi tin nhắn.',
          type: FeedbackType.error,
        );
      }
    }
  }

  String _detectImageMimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _detectVideoMimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'video/mp4';
  }

  String _formatRecordingTimer(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _formatMessageTime(DateTime dt) {
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatDayDivider(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(local.year, local.month, local.day);
    final diff = today.difference(msgDay).inDays;
    final timeStr = _formatMessageTime(local);
    if (diff == 0) return 'Hôm nay, $timeStr';
    if (diff == 1) return 'Hôm qua, $timeStr';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo/${local.year}, $timeStr';
  }

  bool _needsTimeHeader(DmMessage older, DmMessage newer) {
    final gap = newer.createdAt.difference(older.createdAt).abs();
    if (gap.inMinutes >= 30) return true;
    final oLocal = older.createdAt.toLocal();
    final nLocal = newer.createdAt.toLocal();
    return oLocal.year != nLocal.year ||
        oLocal.month != nLocal.month ||
        oLocal.day != nLocal.day;
  }

  bool _canGroupMessages(DmMessage older, DmMessage newer) {
    if (older.isDeleted || newer.isDeleted) return false;
    if (older.senderId != newer.senderId) return false;
    if (_needsTimeHeader(older, newer)) return false;
    return newer.createdAt.difference(older.createdAt).abs().inMinutes < 2;
  }

  void _toggleRevealedTime(String messageId) {
    setState(() {
      _revealedTimeMessageId =
          _revealedTimeMessageId == messageId ? null : messageId;
    });
  }

  Future<void> _startCall(String callType) async {
    final ok = await ref.read(communityCallProvider.notifier).startCall(
          conversationId: widget.conversationId,
          peer: widget.peer,
          callType: callType,
        );
    if (!mounted) return;
    if (!ok) {
      final callState = ref.read(communityCallProvider);
      final err = callState.errorMessage;
      if (err != null && err.isNotEmpty) {
        SamanFeedbackSnackBar.show(
          context,
          message: err,
          type: FeedbackType.warning,
        );
      }
      ref.read(communityCallProvider.notifier).dismissEndedState();
      return;
    }
    if (!CommunityCallScreen.isPresented && mounted) {
      CommunityCallScreen.isPresented = true;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const CommunityCallScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CommunityChatThreadState>(
      communityChatThreadProvider(widget.conversationId),
      (previous, next) {
        final prevTopId = previous != null && previous.messages.isNotEmpty
            ? previous.messages.first.id
            : null;
        final nextTop = next.messages.isNotEmpty ? next.messages.first : null;
        if (nextTop != null &&
            nextTop.id != prevTopId &&
            nextTop.senderId == widget.peer.id) {
          ref
              .read(communityChatThreadProvider(widget.conversationId).notifier)
              .markRead();
        }
        if (next.errorMessage != null &&
            next.errorMessage != previous?.errorMessage) {
          SamanFeedbackSnackBar.show(
            context,
            message: next.errorMessage!,
            type: FeedbackType.error,
          );
        }
      },
    );

    final ig = SamanIgTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(communityChatThreadProvider(widget.conversationId));

    String? newestMyMessageId;
    for (final m in state.messages) {
      if (m.senderId != widget.peer.id) {
        newestMyMessageId = m.id;
        break;
      }
    }

    return CommunityCallHostListener(
      child: Scaffold(
        backgroundColor: ig.canvas,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _ChatThreadAppBar(
                peer: widget.peer,
                peerIsTyping: state.peerIsTyping,
                ig: ig,
                onBack: () => Navigator.pop(context),
                onTapPeer: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.communityProfile,
                    arguments: widget.peer.id,
                  );
                },
                onStartAudioCall: () => _startCall('audio'),
                onStartVideoCall: () => _startCall('video'),
              ),
              Expanded(
                child: _buildMessagesArea(
                  context: context,
                  state: state,
                  newestMyMessageId: newestMyMessageId,
                  ig: ig,
                ),
              ),
              if (_isUploadingMedia)
                Container(
                  width: double.infinity,
                  color: ig.surface,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ig.primaryAction,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Đang tải tệp đa phương tiện...',
                        style: textTheme.labelSmall?.copyWith(
                          fontFamily: SamanIgTokens.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: ig.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              _buildComposerBar(
                context: context,
                ig: ig,
                isSending: state.isSending,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesArea({
    required BuildContext context,
    required CommunityChatThreadState state,
    required String? newestMyMessageId,
    required SamanIgTokens ig,
  }) {
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading && state.messages.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: ig.primaryAction),
      );
    }

    if (state.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PeerCircleAvatar(
                name: widget.peer.name,
                avatarUrl: widget.peer.avatarUrl,
                size: 68,
                ig: ig,
              ),
              const SizedBox(height: 14),
              Text(
                widget.peer.name,
                style: textTheme.titleLarge?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ig.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Hãy gửi lời chào để bắt đầu cuộc trò chuyện với ${widget.peer.name}.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 13.5,
                  color: ig.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final int extraTopTyping = state.peerIsTyping ? 1 : 0;
    final int extraLoadMore = state.isLoadingMore ? 1 : 0;
    final int totalCount =
        state.messages.length + extraTopTyping + extraLoadMore;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (state.peerIsTyping && index == 0) {
          return _TypingIndicatorRow(
            peer: widget.peer,
            ig: ig,
          );
        }

        final msgIndex = index - extraTopTyping;
        if (msgIndex >= state.messages.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ig.primaryAction,
                ),
              ),
            ),
          );
        }

        final msg = state.messages[msgIndex];
        final isMine = msg.senderId != widget.peer.id;
        final showSeen =
            isMine && msg.id == newestMyMessageId && state.peerReadAt != null;

        // Since list is newest-first (0 = bottom), older message is at msgIndex + 1,
        // newer message is at msgIndex - 1.
        final DmMessage? olderMsg = msgIndex + 1 < state.messages.length
            ? state.messages[msgIndex + 1]
            : null;
        final DmMessage? newerMsg =
            msgIndex - 1 >= 0 ? state.messages[msgIndex - 1] : null;

        final bool showTimeDivider =
            olderMsg == null || _needsTimeHeader(olderMsg, msg);
        final bool sameAsPrev =
            olderMsg != null && !showTimeDivider && _canGroupMessages(olderMsg, msg);
        final bool sameAsNext =
            newerMsg != null && _canGroupMessages(msg, newerMsg);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTimeDivider)
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 10),
                child: Center(
                  child: Text(
                    _formatDayDivider(msg.createdAt),
                    style: textTheme.labelSmall?.copyWith(
                      fontFamily: SamanIgTokens.fontFamily,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: ig.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            _MessageRow(
              message: msg,
              peer: widget.peer,
              isMine: isMine,
              sameAsPrev: sameAsPrev,
              sameAsNext: sameAsNext,
              showSeenSpacing: showSeen,
              isTimeRevealed: _revealedTimeMessageId == msg.id,
              formattedTime: _formatMessageTime(msg.createdAt),
              ig: ig,
              onTapBubble: () => _toggleRevealedTime(msg.id),
              onLongPress: isMine && !msg.isDeleted
                  ? () => _confirmDeleteMessage(msg)
                  : null,
              onOpenImage: (url) => DmMediaViewer.showImage(context, url),
              onOpenVideo: (url) => DmMediaViewer.showVideo(context, url),
              onOpenSharedPost: (postId) {
                Navigator.pushNamed(
                  context,
                  AppRoutes.communityPost,
                  arguments: postId,
                );
              },
              onCallAgain: _startCall,
            ),
            if (showSeen)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 6, bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Đã xem',
                      style: textTheme.labelSmall?.copyWith(
                        fontFamily: SamanIgTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: ig.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildComposerBar({
    required BuildContext context,
    required SamanIgTokens ig,
    required bool isSending,
  }) {
    return Container(
      color: ig.canvas,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: _isRecording
              ? _buildRecordingComposer(context, ig)
              : _buildStandardComposer(
                  context: context,
                  ig: ig,
                  isSending: isSending,
                ),
        ),
      ),
    );
  }

  Widget _buildRecordingComposer(
    BuildContext context,
    SamanIgTokens ig,
  ) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: ig.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ig.danger.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          _PulsingRecordDot(color: ig.danger),
          const SizedBox(width: 10),
          Text(
            _formatRecordingTimer(_recordingSeconds),
            style: textTheme.titleSmall?.copyWith(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ig.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Đang ghi âm...',
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                fontFamily: SamanIgTokens.fontFamily,
                fontSize: 13,
                color: ig.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: _cancelVoiceRecording,
            style: TextButton.styleFrom(
              foregroundColor: ig.danger,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              'Hủy',
              style: textTheme.labelLarge?.copyWith(
                fontFamily: SamanIgTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ig.danger,
              ),
            ),
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: 44,
            height: 44,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _stopAndSendVoiceRecording,
                customBorder: const CircleBorder(),
                child: Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: ig.primaryAction,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      size: 18,
                      color: ig.onPrimaryAction,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardComposer({
    required BuildContext context,
    required SamanIgTokens ig,
    required bool isSending,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: ig.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Tooltip(
            message: 'Đính kèm ảnh hoặc video',
            child: SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isUploadingMedia ? null : _showMediaPickerSheet,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Icon(
                      Icons.camera_alt_rounded,
                      size: 22,
                      color: _isUploadingMedia
                          ? ig.textMuted
                          : ig.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: TextField(
                controller: _textController,
                focusNode: _inputFocusNode,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                onChanged: _handleTextChanged,
                style: textTheme.bodyMedium?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 15,
                  color: ig.textPrimary,
                  height: 1.35,
                ),
                decoration: InputDecoration(
                  hintText: 'Nhắn tin...',
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: 15,
                    color: ig.textMuted,
                  ),
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 11,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration:
                disableAnimations ? Duration.zero : const Duration(milliseconds: 160),
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (final prev in previousChildren)
                    IgnorePointer(child: prev),
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: _hasText
                ? SizedBox(
                    key: const ValueKey('dm-composer-send-btn'),
                    width: 44,
                    height: 44,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: isSending ? null : _sendTextMessage,
                        customBorder: const CircleBorder(),
                        child: Center(
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: ig.primaryAction,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.send_rounded,
                              size: 18,
                              color: ig.onPrimaryAction,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : Tooltip(
                    key: const ValueKey('dm-composer-mic-btn'),
                    message: 'Ghi âm tin nhắn thoại',
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap:
                              _isUploadingMedia ? null : _startVoiceRecording,
                          customBorder: const CircleBorder(),
                          child: Center(
                            child: Icon(
                              Icons.mic_rounded,
                              size: 22,
                              color: _isUploadingMedia
                                  ? ig.textMuted
                                  : ig.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChatThreadAppBar extends StatelessWidget {
  final DmParticipant peer;
  final bool peerIsTyping;
  final SamanIgTokens ig;
  final VoidCallback onBack;
  final VoidCallback onTapPeer;
  final VoidCallback onStartAudioCall;
  final VoidCallback onStartVideoCall;

  const _ChatThreadAppBar({
    required this.peer,
    required this.peerIsTyping,
    required this.ig,
    required this.onBack,
    required this.onTapPeer,
    required this.onStartAudioCall,
    required this.onStartVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String? subtitle = peerIsTyping
        ? 'Đang nhập...'
        : (peer.showActivityStatus ? 'Đang hoạt động' : null);

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: ig.canvas,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Quay lại',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: ig.textPrimary,
              size: 22,
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTapPeer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _PeerCircleAvatar(
                          name: peer.name,
                          avatarUrl: peer.avatarUrl,
                          size: 36,
                          ig: ig,
                        ),
                        if (peer.showActivityStatus)
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: ig.primaryAction,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: ig.canvas,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  peer.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleSmall?.copyWith(
                                    fontFamily: SamanIgTokens.fontFamily,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    color: ig.textPrimary,
                                  ),
                                ),
                              ),
                              if (peer.isVerified) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 14,
                                  color: ig.primaryAction,
                                ),
                              ],
                            ],
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                fontFamily: SamanIgTokens.fontFamily,
                                fontSize: 12,
                                fontWeight: peerIsTyping
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: peerIsTyping
                                    ? ig.primaryAction
                                    : ig.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('call-audio-button'),
            onPressed: onStartAudioCall,
            tooltip: context.tr('community_call_audio'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.call_outlined,
              color: ig.textPrimary,
              size: 22,
            ),
          ),
          IconButton(
            key: const Key('call-video-button'),
            onPressed: onStartVideoCall,
            tooltip: context.tr('community_call_video'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.videocam_outlined,
              color: ig.textPrimary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final DmMessage message;
  final DmParticipant peer;
  final bool isMine;
  final bool sameAsPrev;
  final bool sameAsNext;
  final bool showSeenSpacing;
  final bool isTimeRevealed;
  final String formattedTime;
  final SamanIgTokens ig;
  final VoidCallback onTapBubble;
  final VoidCallback? onLongPress;
  final ValueChanged<String> onOpenImage;
  final ValueChanged<String> onOpenVideo;
  final ValueChanged<String> onOpenSharedPost;
  final ValueChanged<String>? onCallAgain;

  const _MessageRow({
    required this.message,
    required this.peer,
    required this.isMine,
    required this.sameAsPrev,
    required this.sameAsNext,
    required this.showSeenSpacing,
    required this.isTimeRevealed,
    required this.formattedTime,
    required this.ig,
    required this.onTapBubble,
    required this.onLongPress,
    required this.onOpenImage,
    required this.onOpenVideo,
    required this.onOpenSharedPost,
    this.onCallAgain,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = screenWidth * 0.74;
    final maxMediaWidth = screenWidth * 0.70;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: showSeenSpacing ? 0 : (sameAsNext ? 2.5 : 12),
      ),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            if (!sameAsNext)
              _PeerCircleAvatar(
                name: peer.name,
                avatarUrl: peer.avatarUrl,
                size: 28,
                ig: ig,
              )
            else
              const SizedBox(width: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTapBubble,
                onLongPress: onLongPress,
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    _buildBubbleContent(context, maxMediaWidth: maxMediaWidth),
                    AnimatedSize(
                      duration: disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: isTimeRevealed
                          ? Padding(
                              padding: const EdgeInsets.only(
                                top: 4,
                                left: 6,
                                right: 6,
                                bottom: 2,
                              ),
                              child: Text(
                                formattedTime,
                                style: textTheme.labelSmall?.copyWith(
                                  fontFamily: SamanIgTokens.fontFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: ig.textMuted,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BorderRadius _bubbleRadius() {
    if (isMine) {
      return BorderRadius.only(
        topLeft: const Radius.circular(20),
        bottomLeft: const Radius.circular(20),
        topRight: Radius.circular(sameAsPrev ? 5 : 20),
        bottomRight: Radius.circular(sameAsNext ? 5 : 20),
      );
    }
    return BorderRadius.only(
      topRight: const Radius.circular(20),
      bottomRight: const Radius.circular(20),
      topLeft: Radius.circular(sameAsPrev ? 5 : 20),
      bottomLeft: Radius.circular(sameAsNext ? 5 : 20),
    );
  }

  BoxDecoration _myBubbleDecoration() {
    return BoxDecoration(
      gradient: SamanIgTokens.dmSentGradient,
      borderRadius: _bubbleRadius(),
    );
  }

  BoxDecoration _peerBubbleDecoration() {
    return BoxDecoration(
      color: ig.dmBubbleReceived,
      borderRadius: _bubbleRadius(),
    );
  }

  BoxDecoration _surfaceDecoration() {
    return isMine ? _myBubbleDecoration() : _peerBubbleDecoration();
  }

  Widget _buildBubbleContent(
    BuildContext context, {
    required double maxMediaWidth,
  }) {
    final textTheme = Theme.of(context).textTheme;

    if (message.isDeleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ig.surface,
          borderRadius: _bubbleRadius(),
          border: Border.all(color: ig.border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block_rounded,
              size: 14,
              color: ig.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Tin nhắn đã bị thu hồi',
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                  color: ig.textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    switch (message.type) {
      case DmMessageType.voice:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: _surfaceDecoration(),
          child: DmVoiceBubble(
            mediaUrl: message.mediaUrl ?? '',
            durationSeconds: message.durationSeconds,
            isMine: isMine,
            tokens: ig,
          ),
        );

      case DmMessageType.photo:
        return _buildPhotoBubble(context, maxMediaWidth: maxMediaWidth);

      case DmMessageType.video:
        return _buildVideoBubble(context, maxMediaWidth: maxMediaWidth);

      case DmMessageType.postShare:
        return _buildPostShareBubble(context, maxMediaWidth: maxMediaWidth);

      case DmMessageType.storyReply:
        return _buildStoryReplyBubble(context);

      case DmMessageType.callLog:
        return _buildCallLogBubble(context);

      case DmMessageType.text:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: _surfaceDecoration(),
          child: Text(
            message.content,
            style: textTheme.bodyMedium?.copyWith(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 15,
              height: 1.35,
              color: isMine ? ig.onPrimaryAction : ig.textPrimary,
            ),
          ),
        );
    }
  }

  Widget _buildCallLogBubble(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final status = (message.callStatus ?? '').toLowerCase();
    final isVideo = (message.callType ?? '').toLowerCase() == 'video';
    final isMissedOrRejected = status == 'missed' || status == 'rejected';
    final iconColor = isMissedOrRejected ? ig.danger : ig.textPrimary;

    final IconData leadingIcon;
    if (isVideo) {
      leadingIcon = isMissedOrRejected
          ? Icons.videocam_off_outlined
          : Icons.videocam_outlined;
    } else {
      leadingIcon = isMissedOrRejected
          ? Icons.phone_missed_rounded
          : Icons.call_outlined;
    }

    final String titleText;
    if (status == 'missed') {
      titleText = isVideo
          ? context.tr('community_call_missed_video')
          : context.tr('community_call_missed_audio');
    } else if (status == 'rejected') {
      titleText = isVideo
          ? context.tr('community_call_rejected_video')
          : context.tr('community_call_rejected_audio');
    } else {
      titleText = isVideo
          ? context.tr('community_call_video')
          : context.tr('community_call_audio');
    }

    final String subtitleText;
    if (status == 'completed') {
      subtitleText = formatDmCallDuration(message.durationSec);
    } else if (message.content.trim().isNotEmpty &&
        message.content.trim() != titleText) {
      subtitleText = message.content.trim();
    } else {
      subtitleText = isMissedOrRejected
          ? context.tr('community_call_again')
          : formatDmCallDuration(message.durationSec);
    }

    return Container(
      key: ValueKey('call-log-bubble-${message.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMissedOrRejected
                  ? ig.danger.withOpacity(0.14)
                  : ig.surfaceElevated,
            ),
            child: Icon(
              leadingIcon,
              size: 19,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleText,
                  style: textTheme.titleSmall?.copyWith(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isMissedOrRejected ? ig.danger : ig.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: textTheme.bodySmall?.copyWith(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: 12.5,
                    color: ig.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (onCallAgain != null) ...[
            const SizedBox(width: 12),
            TextButton(
              key: ValueKey('call-log-again-${message.id}'),
              onPressed: () => onCallAgain!(isVideo ? 'video' : 'audio'),
              style: TextButton.styleFrom(
                foregroundColor: ig.primaryAction,
                backgroundColor: ig.primaryAction.withOpacity(0.12),
                minimumSize: const Size(44, 36),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                context.tr('community_call_again'),
                style: textTheme.labelMedium?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: ig.primaryAction,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoryReplyBubble(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fgColor = isMine ? ig.onPrimaryAction : ig.textPrimary;
    final quoteColor =
        isMine ? ig.onPrimaryAction.withOpacity(0.88) : ig.primaryAction;
    final quoteBg =
        isMine ? ig.onPrimaryAction.withOpacity(0.16) : ig.surface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _surfaceDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: quoteBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  size: 13,
                  color: quoteColor,
                ),
                const SizedBox(width: 5),
                Text(
                  'Đã trả lời tin',
                  style: textTheme.labelSmall?.copyWith(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: quoteColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message.content.isNotEmpty
                ? message.content
                : 'Đã phản hồi tin 24h',
            style: textTheme.bodyMedium?.copyWith(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 15,
              height: 1.35,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoBubble(
    BuildContext context, {
    required double maxMediaWidth,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final url = message.mediaUrl ?? '';
    final width = maxMediaWidth.clamp(180.0, 260.0);

    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: url.isNotEmpty ? () => onOpenImage(url) : null,
          child: Container(
            width: width,
            height: 210,
            decoration: BoxDecoration(
              color: ig.surfaceElevated,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: url.isNotEmpty
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ig.primaryAction,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            color: ig.textMuted,
                            size: 28,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Không thể tải ảnh',
                            style: textTheme.labelSmall?.copyWith(
                              fontFamily: SamanIgTokens.fontFamily,
                              fontSize: 11.5,
                              color: ig.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: ig.textMuted,
                      size: 32,
                    ),
                  ),
          ),
        ),
        if (message.content.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: _surfaceDecoration(),
            child: Text(
              message.content,
              style: textTheme.bodyMedium?.copyWith(
                fontFamily: SamanIgTokens.fontFamily,
                fontSize: 15,
                height: 1.35,
                color: isMine ? ig.onPrimaryAction : ig.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVideoBubble(
    BuildContext context, {
    required double maxMediaWidth,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final url = message.mediaUrl ?? '';
    final width = maxMediaWidth.clamp(180.0, 260.0);
    final durationLabel = message.durationSeconds != null &&
            message.durationSeconds! > 0
        ? '${message.durationSeconds!.round() ~/ 60}:${(message.durationSeconds!.round() % 60).toString().padLeft(2, '0')}'
        : 'Video';

    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: url.isNotEmpty ? () => onOpenVideo(url) : null,
          child: Container(
            width: width,
            height: 168,
            decoration: BoxDecoration(
              color: ig.surfaceElevated,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Icon(
                    Icons.videocam_rounded,
                    size: 42,
                    color: ig.textMuted.withOpacity(0.32),
                  ),
                ),
                Container(
                  color: Colors.black.withOpacity(0.18),
                ),
                Center(
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.36),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.32),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      durationLabel,
                      style: textTheme.labelSmall?.copyWith(
                        fontFamily: SamanIgTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (message.content.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: _surfaceDecoration(),
            child: Text(
              message.content,
              style: textTheme.bodyMedium?.copyWith(
                fontFamily: SamanIgTokens.fontFamily,
                fontSize: 15,
                height: 1.35,
                color: isMine ? ig.onPrimaryAction : ig.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPostShareBubble(
    BuildContext context, {
    required double maxMediaWidth,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final preview = message.sharedPostPreview;
    final postId = message.sharedPostId ?? preview?.id;
    final cardWidth = maxMediaWidth.clamp(210.0, 256.0);
    final hasThumbnail =
        preview?.thumbnailUrl != null && preview!.thumbnailUrl!.isNotEmpty;

    return InkWell(
      onTap: postId != null && postId.isNotEmpty
          ? () => onOpenSharedPost(postId)
          : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          color: ig.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: ig.border,
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasThumbnail)
              SizedBox(
                width: double.infinity,
                height: 140,
                child: Image.network(
                  preview.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: ig.surfaceElevated,
                    child: Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: ig.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 14,
                        color: ig.primaryAction,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          preview?.authorName ?? 'Bài viết cộng đồng',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            fontFamily: SamanIgTokens.fontFamily,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: ig.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (preview?.caption.isNotEmpty ?? false)
                        ? preview!.caption
                        : (message.content.isNotEmpty
                            ? message.content
                            : 'Xem bài viết đã chia sẻ trong cộng đồng Saman'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: SamanIgTokens.fontFamily,
                      fontSize: 13,
                      color: ig.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: ig.primaryAction.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Xem bài viết',
                          style: textTheme.labelSmall?.copyWith(
                            fontFamily: SamanIgTokens.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ig.primaryAction,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: ig.primaryAction,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicatorRow extends StatelessWidget {
  final DmParticipant peer;
  final SamanIgTokens ig;

  const _TypingIndicatorRow({
    required this.peer,
    required this.ig,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _PeerCircleAvatar(
            name: peer.name,
            avatarUrl: peer.avatarUrl,
            size: 28,
            ig: ig,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: ig.dmBubbleReceived,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Đang nhập',
                  style: textTheme.labelSmall?.copyWith(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: ig.primaryAction,
                  ),
                ),
                const SizedBox(width: 6),
                _TypingDot(color: ig.primaryAction, opacity: 1.0),
                const SizedBox(width: 3),
                _TypingDot(color: ig.primaryAction, opacity: 0.65),
                const SizedBox(width: 3),
                _TypingDot(color: ig.primaryAction, opacity: 0.35),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDot extends StatelessWidget {
  final Color color;
  final double opacity;

  const _TypingDot({required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: color.withOpacity(opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _PulsingRecordDot extends StatefulWidget {
  final Color color;

  const _PulsingRecordDot({required this.color});

  @override
  State<_PulsingRecordDot> createState() => _PulsingRecordDotState();
}

class _PulsingRecordDotState extends State<_PulsingRecordDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }

    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _MediaPickerOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final SamanIgTokens ig;
  final VoidCallback onTap;

  const _MediaPickerOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ig,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ig.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ig.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ig.primaryAction.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: ig.primaryAction),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontFamily: SamanIgTokens.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ig.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: SamanIgTokens.fontFamily,
                      fontSize: 12,
                      color: ig.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: ig.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerCircleAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double size;
  final SamanIgTokens ig;

  const _PeerCircleAvatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
    required this.ig,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'S';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ig.surfaceElevated,
        border: Border.all(color: ig.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  initial,
                  style: textTheme.titleSmall?.copyWith(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w700,
                    color: ig.primaryAction,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initial,
                style: textTheme.titleSmall?.copyWith(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w700,
                  color: ig.primaryAction,
                ),
              ),
            ),
    );
  }
}
