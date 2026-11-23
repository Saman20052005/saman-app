import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../../../config/routes.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../data/datasources/community_dm_ws_service.dart';
import '../../../domain/models/community_dm.dart';
import '../../providers/community_dm_provider.dart';
import '../../providers/community_providers.dart';
import '../../widgets/dm_media_viewer.dart';
import '../../widgets/dm_voice_bubble.dart';

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
    final tokens = SamanHomeTokens.of(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.cardSurface,
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
                    color: tokens.borderHigh,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Đính kèm đa phương tiện',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _MediaPickerOptionTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Chọn ảnh',
                  subtitle: 'Gửi hình ảnh từ thư viện thiết bị',
                  tokens: tokens,
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
                  tokens: tokens,
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
                  tokens: tokens,
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
    final tokens = SamanHomeTokens.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: tokens.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: tokens.border),
          ),
          title: Text(
            'Thu hồi tin nhắn?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          content: Text(
            'Tin nhắn này sẽ bị thu hồi cho cả hai phía trong cuộc trò chuyện.',
            style: TextStyle(
              fontSize: 14,
              color: tokens.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Hủy',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Thu hồi',
                style: TextStyle(
                  color: tokens.fatRose,
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

    final tokens = SamanHomeTokens.of(context);
    final state = ref.watch(communityChatThreadProvider(widget.conversationId));

    String? newestMyMessageId;
    for (final m in state.messages) {
      if (m.senderId != widget.peer.id) {
        newestMyMessageId = m.id;
        break;
      }
    }

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ChatThreadAppBar(
              peer: widget.peer,
              peerIsTyping: state.peerIsTyping,
              tokens: tokens,
              onBack: () => Navigator.pop(context),
              onTapPeer: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.communityProfile,
                  arguments: widget.peer.id,
                );
              },
            ),
            Expanded(
              child: _buildMessagesArea(
                state: state,
                newestMyMessageId: newestMyMessageId,
                tokens: tokens,
              ),
            ),
            if (_isUploadingMedia)
              Container(
                width: double.infinity,
                color: tokens.cardSurface,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.greenAccent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Đang tải tệp đa phương tiện...',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            _buildComposerBar(tokens: tokens, isSending: state.isSending),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesArea({
    required CommunityChatThreadState state,
    required String? newestMyMessageId,
    required SamanHomePalette tokens,
  }) {
    if (state.isLoading && state.messages.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: tokens.greenAccent),
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
                size: 64,
                tokens: tokens,
              ),
              const SizedBox(height: 14),
              Text(
                widget.peer.name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Hãy gửi lời chào để bắt đầu cuộc trò chuyện với ${widget.peer.name}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: tokens.textSecondary,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (state.peerIsTyping && index == 0) {
          return _TypingIndicatorRow(
            peer: widget.peer,
            tokens: tokens,
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
                  color: tokens.greenAccent,
                ),
              ),
            ),
          );
        }

        final msg = state.messages[msgIndex];
        final isMine = msg.senderId != widget.peer.id;
        final showSeen =
            isMine && msg.id == newestMyMessageId && state.peerReadAt != null;

        // Since list is newest-first, older message is at msgIndex + 1.
        bool showTimeDivider = false;
        if (msgIndex == state.messages.length - 1) {
          showTimeDivider = true;
        } else {
          final older = state.messages[msgIndex + 1];
          final gap = msg.createdAt.difference(older.createdAt).abs();
          if (gap.inMinutes >= 30 ||
              msg.createdAt.toLocal().day != older.createdAt.toLocal().day) {
            showTimeDivider = true;
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTimeDivider)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tokens.cardSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Text(
                      _formatDayDivider(msg.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: tokens.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            _MessageRow(
              message: msg,
              peer: widget.peer,
              isMine: isMine,
              formattedTime: _formatMessageTime(msg.createdAt),
              tokens: tokens,
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
            ),
            if (showSeen)
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 4, bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.done_all_rounded,
                      size: 13,
                      color: tokens.greenAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Đã xem',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: tokens.textMuted,
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
    required SamanHomePalette tokens,
    required bool isSending,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(top: BorderSide(color: tokens.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: _isRecording
              ? _buildRecordingComposer(tokens)
              : _buildStandardComposer(tokens: tokens, isSending: isSending),
        ),
      ),
    );
  }

  Widget _buildRecordingComposer(SamanHomePalette tokens) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.fatRose.withOpacity(0.55)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: tokens.fatRose,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatRecordingTimer(_recordingSeconds),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Đang ghi âm...',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: _cancelVoiceRecording,
            style: TextButton.styleFrom(
              foregroundColor: tokens.fatRose,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(44, 36),
            ),
            child: const Text(
              'Hủy',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: tokens.greenAccent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _stopAndSendVoiceRecording,
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.send_rounded,
                  size: 18,
                  color: tokens.primaryCtaText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardComposer({
    required SamanHomePalette tokens,
    required bool isSending,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Material(
          color: tokens.secondarySurface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: _isUploadingMedia ? null : _showMediaPickerSheet,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.border),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 22,
                color: _isUploadingMedia
                    ? tokens.textMuted
                    : tokens.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _textController,
            focusNode: _inputFocusNode,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            onChanged: _handleTextChanged,
            style: TextStyle(
              fontSize: 14,
              color: tokens.textPrimary,
              height: 1.35,
            ),
            decoration: InputDecoration(
              hintText: 'Nhắn tin...',
              hintStyle: TextStyle(
                fontSize: 14,
                color: tokens.textMuted,
              ),
              filled: true,
              fillColor: tokens.cardSurface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.greenAccent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_hasText)
          Material(
            color: tokens.greenAccent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: isSending ? null : _sendTextMessage,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: tokens.primaryCtaText,
                ),
              ),
            ),
          )
        else
          Material(
            color: tokens.secondarySurface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _isUploadingMedia ? null : _startVoiceRecording,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border),
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 20,
                  color: _isUploadingMedia
                      ? tokens.textMuted
                      : tokens.greenAccent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatThreadAppBar extends StatelessWidget {
  final DmParticipant peer;
  final bool peerIsTyping;
  final SamanHomePalette tokens;
  final VoidCallback onBack;
  final VoidCallback onTapPeer;

  const _ChatThreadAppBar({
    required this.peer,
    required this.peerIsTyping,
    required this.tokens,
    required this.onBack,
    required this.onTapPeer,
  });

  @override
  Widget build(BuildContext context) {
    final String? subtitle = peerIsTyping
        ? 'Đang nhập...'
        : (peer.showActivityStatus ? 'Đang hoạt động' : null);

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Quay lại',
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTapPeer,
              borderRadius: BorderRadius.circular(10),
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
                          tokens: tokens,
                        ),
                        if (peer.showActivityStatus)
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: tokens.greenAccent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: tokens.canvas,
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
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                              if (peer.isVerified) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 14,
                                  color: tokens.greenAccent,
                                ),
                              ],
                            ],
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: peerIsTyping
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: peerIsTyping
                                    ? tokens.greenAccent
                                    : tokens.textSecondary,
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
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final DmMessage message;
  final DmParticipant peer;
  final bool isMine;
  final String formattedTime;
  final SamanHomePalette tokens;
  final VoidCallback? onLongPress;
  final ValueChanged<String> onOpenImage;
  final ValueChanged<String> onOpenVideo;
  final ValueChanged<String> onOpenSharedPost;

  const _MessageRow({
    required this.message,
    required this.peer,
    required this.isMine,
    required this.formattedTime,
    required this.tokens,
    required this.onLongPress,
    required this.onOpenImage,
    required this.onOpenVideo,
    required this.onOpenSharedPost,
  });

  @override
  Widget build(BuildContext context) {
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.74;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            _PeerCircleAvatar(
              name: peer.name,
              avatarUrl: peer.avatarUrl,
              size: 28,
              tokens: tokens,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    _buildBubbleContent(context),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        formattedTime,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: tokens.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
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
    return BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMine ? 16 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 16),
    );
  }

  Widget _buildBubbleContent(BuildContext context) {
    if (message.isDeleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.cardSurface,
          borderRadius: _bubbleRadius(),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block_rounded,
              size: 14,
              color: tokens.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Tin nhắn đã bị thu hồi',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: tokens.textMuted,
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
          decoration: BoxDecoration(
            color: isMine ? tokens.greenAccent : tokens.cardSurface,
            borderRadius: _bubbleRadius(),
            border: isMine ? null : Border.all(color: tokens.border),
          ),
          child: DmVoiceBubble(
            mediaUrl: message.mediaUrl ?? '',
            durationSeconds: message.durationSeconds,
            isMine: isMine,
            tokens: tokens,
          ),
        );

      case DmMessageType.photo:
        return _buildPhotoBubble();

      case DmMessageType.video:
        return _buildVideoBubble();

      case DmMessageType.postShare:
        return _buildPostShareBubble();

      case DmMessageType.storyReply:
        return _buildStoryReplyBubble();

      case DmMessageType.text:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMine ? tokens.greenAccent : tokens.cardSurface,
            borderRadius: _bubbleRadius(),
            border: isMine ? null : Border.all(color: tokens.border),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: isMine ? tokens.primaryCtaText : tokens.textPrimary,
            ),
          ),
        );
    }
  }

  Widget _buildStoryReplyBubble() {
    final fgColor = isMine ? tokens.primaryCtaText : tokens.textPrimary;
    final quoteColor = isMine
        ? tokens.primaryCtaText.withOpacity(0.75)
        : tokens.greenAccent;
    final quoteBg = isMine
        ? tokens.primaryCtaText.withOpacity(0.12)
        : tokens.secondarySurface;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine ? tokens.greenAccent : tokens.cardSurface,
        borderRadius: _bubbleRadius(),
        border: isMine ? null : Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: quoteBg,
              borderRadius: BorderRadius.circular(8),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: quoteColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message.content.isNotEmpty ? message.content : 'Đã phản hồi tin 24h',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoBubble() {
    final url = message.mediaUrl ?? '';
    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: url.isNotEmpty ? () => onOpenImage(url) : null,
          child: Container(
            width: 224,
            height: 200,
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border),
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
                            color: tokens.greenAccent,
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
                            color: tokens.textMuted,
                            size: 28,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Không thể tải ảnh',
                            style: TextStyle(
                              fontSize: 11,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: tokens.textMuted,
                      size: 32,
                    ),
                  ),
          ),
        ),
        if (message.content.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMine ? tokens.greenAccent : tokens.cardSurface,
              borderRadius: _bubbleRadius(),
              border: isMine ? null : Border.all(color: tokens.border),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                fontSize: 13,
                color: isMine ? tokens.primaryCtaText : tokens.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVideoBubble() {
    final url = message.mediaUrl ?? '';
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
            width: 224,
            height: 152,
            decoration: BoxDecoration(
              color: tokens.secondarySurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Icon(
                    Icons.videocam_rounded,
                    size: 42,
                    color: tokens.textMuted.withOpacity(0.35),
                  ),
                ),
                Container(
                  color: tokens.canvas.withOpacity(0.28),
                ),
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: tokens.greenAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 30,
                      color: tokens.primaryCtaText,
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
                      color: tokens.canvas.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      durationLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMine ? tokens.greenAccent : tokens.cardSurface,
              borderRadius: _bubbleRadius(),
              border: isMine ? null : Border.all(color: tokens.border),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                fontSize: 13,
                color: isMine ? tokens.primaryCtaText : tokens.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPostShareBubble() {
    final preview = message.sharedPostPreview;
    final postId = message.sharedPostId ?? preview?.id;

    return InkWell(
      onTap: postId != null && postId.isNotEmpty
          ? () => onOpenSharedPost(postId)
          : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: tokens.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMine ? tokens.greenBadgeBorder : tokens.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 15,
                    color: tokens.greenAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      preview?.authorName ?? 'Bài viết cộng đồng',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (preview?.thumbnailUrl != null &&
                preview!.thumbnailUrl!.isNotEmpty)
              SizedBox(
                width: double.infinity,
                height: 120,
                child: Image.network(
                  preview.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: tokens.secondarySurface,
                    child: Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (preview?.caption.isNotEmpty ?? false)
                        ? preview!.caption
                        : (message.content.isNotEmpty
                            ? message.content
                            : 'Xem bài viết đã chia sẻ trong cộng đồng Saman'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: tokens.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Xem bài viết',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.greenAccent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: tokens.greenAccent,
                      ),
                    ],
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
  final SamanHomePalette tokens;

  const _TypingIndicatorRow({
    required this.peer,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _PeerCircleAvatar(
            name: peer.name,
            avatarUrl: peer.avatarUrl,
            size: 28,
            tokens: tokens,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Đang nhập',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: tokens.greenAccent,
                  ),
                ),
                const SizedBox(width: 6),
                _TypingDot(color: tokens.greenAccent, opacity: 1.0),
                const SizedBox(width: 3),
                _TypingDot(color: tokens.greenAccent, opacity: 0.65),
                const SizedBox(width: 3),
                _TypingDot(color: tokens.greenAccent, opacity: 0.35),
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

class _MediaPickerOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final SamanHomePalette tokens;
  final VoidCallback onTap;

  const _MediaPickerOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.secondarySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tokens.greenBadgeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: tokens.greenAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: tokens.textMuted,
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
  final SamanHomePalette tokens;

  const _PeerCircleAvatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'S';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tokens.secondarySurface,
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w700,
                    color: tokens.greenAccent,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w700,
                  color: tokens.greenAccent,
                ),
              ),
            ),
    );
  }
}
