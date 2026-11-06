import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/community_post.dart';
import '../../domain/models/post_attachment_snapshot.dart';
import '../../domain/models/draft_post.dart';
import '../../domain/repositories/community_repository.dart';
import 'community_providers.dart';

class CommunityComposerState {
  final List<String> selectedMediaUrls;
  final int activeMediaIndex;
  final String aspectRatio; // '1:1', '4:5', 'orig'
  final int rotation; // 0, 90, 180, 270
  final double brightness; // -50 to 50
  final double contrast; // -50 to 50
  final bool isGridOverlayVisible;
  final String caption;
  final String questionDetails;
  final String audience;
  final String topic;
  final bool allowComments;
  final PostAttachmentSnapshot? attachedActivity;
  final bool isSubmitting;
  final bool hasPendingSubmission;
  final String? errorMessage;

  const CommunityComposerState({
    this.selectedMediaUrls = const [],
    this.activeMediaIndex = 0,
    this.aspectRatio = '1:1',
    this.rotation = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.isGridOverlayVisible = true,
    this.caption = '',
    this.questionDetails = '',
    this.audience = 'Công khai',
    this.topic = '#BữaĂn',
    this.allowComments = true,
    this.attachedActivity,
    this.isSubmitting = false,
    this.hasPendingSubmission = false,
    this.errorMessage,
  });

  bool get hasContent =>
      caption.trim().isNotEmpty ||
      selectedMediaUrls.isNotEmpty ||
      attachedActivity != null;

  CommunityComposerState copyWith({
    List<String>? selectedMediaUrls,
    int? activeMediaIndex,
    String? aspectRatio,
    int? rotation,
    double? brightness,
    double? contrast,
    bool? isGridOverlayVisible,
    String? caption,
    String? questionDetails,
    String? audience,
    String? topic,
    bool? allowComments,
    PostAttachmentSnapshot? attachedActivity,
    bool clearAttachment = false,
    bool? isSubmitting,
    bool? hasPendingSubmission,
    String? errorMessage,
  }) {
    return CommunityComposerState(
      selectedMediaUrls: selectedMediaUrls ?? this.selectedMediaUrls,
      activeMediaIndex: activeMediaIndex ?? this.activeMediaIndex,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      rotation: rotation ?? this.rotation,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      isGridOverlayVisible: isGridOverlayVisible ?? this.isGridOverlayVisible,
      caption: caption ?? this.caption,
      questionDetails: questionDetails ?? this.questionDetails,
      audience: audience ?? this.audience,
      topic: topic ?? this.topic,
      allowComments: allowComments ?? this.allowComments,
      attachedActivity:
          clearAttachment ? null : (attachedActivity ?? this.attachedActivity),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      hasPendingSubmission: hasPendingSubmission ?? this.hasPendingSubmission,
      errorMessage: errorMessage,
    );
  }
}

class CommunityComposerNotifier
    extends StateNotifier<CommunityComposerState> {
  final CommunityRepository _repository;
  final Ref _ref;
  final bool isQuestion;

  int _generation = 0;
  String? _requestKey;
  CommunityComposerState? _pending;
  CommunityComposerNotifier(this._repository, this._ref, {this.isQuestion = false})
      : super(CommunityComposerState(topic: isQuestion ? 'Dinh dưỡng' : '#BữaĂn'));

  void clearMedia() {
    if (state.isSubmitting) return;
    state = state.copyWith(selectedMediaUrls: const []);
  }

  void setInitialMedia(List<String> urls) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(
      selectedMediaUrls: urls,
      activeMediaIndex: 0,
    );
  }

  void setActiveMediaIndex(int index) {
    if (state.hasPendingSubmission) return;
    if (index >= 0 && index < state.selectedMediaUrls.length) {
      state = state.copyWith(activeMediaIndex: index);
    }
  }

  void setAspectRatio(String ratio) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(aspectRatio: ratio);
  }

  void rotate() {
    if (state.hasPendingSubmission) return;
    final nextRotation = (state.rotation + 90) % 360;
    state = state.copyWith(rotation: nextRotation);
  }

  void setBrightness(double value) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(brightness: value);
  }

  void setContrast(double value) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(contrast: value);
  }

  void resetAdjustments() {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(
      aspectRatio: '1:1',
      rotation: 0,
      brightness: 0,
      contrast: 0,
    );
  }

  void toggleGrid() {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(isGridOverlayVisible: !state.isGridOverlayVisible);
  }

  void reorderMedia(int oldIndex, int newIndex) {
    if (state.hasPendingSubmission) return;
    final list = List<String>.from(state.selectedMediaUrls);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = state.copyWith(selectedMediaUrls: list);
  }

  void removeMedia(int index) {
    if (state.hasPendingSubmission) return;
    final list = List<String>.from(state.selectedMediaUrls)..removeAt(index);
    final newActive = state.activeMediaIndex >= list.length
        ? (list.isEmpty ? 0 : list.length - 1)
        : state.activeMediaIndex;
    state = state.copyWith(
      selectedMediaUrls: list,
      activeMediaIndex: newActive,
    );
  }

  void setCaption(String text) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(caption: text);
  }

  void setQuestionDetails(String text) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(questionDetails: text);
  }

  void setAudience(String audience) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(audience: audience);
  }

  void setTopic(String topic) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(topic: topic);
  }

  void toggleAllowComments() {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(allowComments: !state.allowComments);
  }

  void setAttachment(PostAttachmentSnapshot? attachment) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(attachedActivity: attachment);
  }

  void clearAttachment() {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(clearAttachment: true);
  }

  DraftPost toDraft() {
    return DraftPost(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      caption: state.caption,
      mediaUrls: state.selectedMediaUrls,
      aspectRatio: state.aspectRatio,
      rotation: state.rotation,
      brightness: state.brightness,
      contrast: state.contrast,
      audience: state.audience,
      topic: state.topic,
      allowComments: state.allowComments,
      attachment: state.attachedActivity,
      updatedAt: DateTime.now(),
    );
  }

  void restoreFromDraft(DraftPost draft) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(
      caption: draft.caption,
      selectedMediaUrls: draft.mediaUrls,
      aspectRatio: draft.aspectRatio,
      rotation: draft.rotation,
      brightness: draft.brightness,
      contrast: draft.contrast,
      audience: draft.audience,
      topic: draft.topic,
      allowComments: draft.allowComments,
      attachedActivity: draft.attachment,
    );
  }

  Future<CommunityPost?> publish() async {
    if (state.isSubmitting) return null;
    final draft = _pending ?? state;
    if (!draft.hasContent || (isQuestion && draft.caption.trim().isEmpty) || draft.caption.length > (isQuestion ? 150 : 5000) || (isQuestion && draft.questionDetails.length > 2000)) {
      state = state.copyWith(errorMessage: isQuestion ? 'community_question_invalid' : 'community_publish_invalid'); return null;
    }
    final generation = _generation;
    final recovering = _requestKey != null;
    _requestKey ??= List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join();
    _pending ??= draft;
    state = state.copyWith(isSubmitting: true, hasPendingSubmission: true);
    try {
      final post = isQuestion
          ? await _repository.publishQuestion(question: draft.caption.trim(), details: draft.questionDetails.trim(),
              categoryTag: draft.topic, audience: draft.audience, requestKey: _requestKey)
          : await _repository.publishPost(caption: draft.caption.trim(), mediaUrls: draft.selectedMediaUrls,
          attachment: draft.attachedActivity, audience: draft.audience, topic: draft.topic,
          allowComments: draft.allowComments, requestKey: _requestKey);
      if (!mounted || generation != _generation) return null;
      _ref.read(communityFeedProvider.notifier).acceptPublished(post);
      _pending = null; _requestKey = null;
      state = CommunityComposerState(topic: isQuestion ? 'Dinh dưỡng' : '#BữaĂn');
      return post;
    } catch (e) {
      if (!mounted || generation != _generation) return null;
      final status = e is DioException ? e.response?.statusCode : null;
      final localRejection = e is UnsupportedError || e is ArgumentError;
      final definitive = !recovering && (localRejection || (status != null && status >= 400 && status < 500 && status != 404 && status != 408));
      if (definitive) { _requestKey = null; _pending = null; }
      state = state.copyWith(isSubmitting: false, hasPendingSubmission: !definitive,
          errorMessage: localRejection && !recovering ? (e is UnsupportedError ? e.message : 'community_publish_invalid')
            : definitive ? (status == 409 && draft.attachedActivity != null ? 'community_attachment_review' : 'community_publish_rejected') : 'community_publish_unconfirmed');
      return null;
    }
  }

  void reset() {
    _generation++;
    _requestKey = null; _pending = null;
    state = CommunityComposerState(topic: isQuestion ? 'Dinh dưỡng' : '#BữaĂn');
  }
}

final communityComposerProvider = StateNotifierProvider<
    CommunityComposerNotifier, CommunityComposerState>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  return CommunityComposerNotifier(repo, ref);
});


final communityQuestionComposerProvider = StateNotifierProvider<
    CommunityComposerNotifier, CommunityComposerState>((ref) {
  return CommunityComposerNotifier(ref.watch(communityRepositoryProvider), ref, isQuestion: true);
});
