import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/models/exercise.dart';
import '../../../../models/meal_log.dart';
import '../../../../presentation/providers/workout_history_providers.dart';
import '../../../../providers/daily_story_provider.dart';
import '../../../../widgets/saman_feedback_snackbar.dart';
import '../../data/datasources/community_remote_datasource.dart';
import '../../domain/models/community_story.dart';
import '../providers/community_providers.dart';
import '../providers/community_social_providers.dart';
import '../tokens/saman_ig_tokens.dart';

class CommunityCreateStorySheet extends ConsumerStatefulWidget {
  const CommunityCreateStorySheet({super.key});

  static Future<CommunityStory?> show(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ig = SamanIgTokens.of(context);

    final story = await showModalBottomSheet<CommunityStory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const CommunityCreateStorySheet(),
    );

    if (story != null && messenger != null && context.mounted) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SamanFeedbackSnackBar.build(
          context: context,
          message: 'Đã đăng tin 24h thành công',
          type: FeedbackType.success,
        ),
      );
    } else if (story != null && messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: isDark
              ? SamanFeedbackSnackBar.darkBg
              : SamanFeedbackSnackBar.lightBg,
          content: const Text('Đã đăng tin 24h thành công'),
        ),
      );
    }

    return story;
  }

  @override
  ConsumerState<CommunityCreateStorySheet> createState() =>
      _CommunityCreateStorySheetState();
}

class _CommunityCreateStorySheetState
    extends ConsumerState<CommunityCreateStorySheet> {
  static const List<String> _bgHexPresets = <String>[
    '#0095F6',
    '#1E293B',
    '#D62976',
    '#4F5BD5',
    '#7C2D12',
  ];

  final TextEditingController _captionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _mediaType = 'text'; // 'text' | 'photo' | 'video'
  String _selectedBgHex = _bgHexPresets.first;
  String _privacy = 'public'; // 'public' | 'followers_only'

  XFile? _pickedFile;
  Uint8List? _pickedBytes;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Optional Saman Check-in sticker state (Privacy-by-Design: metrics hidden by default)
  bool _showSamanCheckIn = false;
  WorkoutSession? _selectedWorkout;
  MealLog? _selectedMeal;
  bool _includeDetailedMetrics = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  String _todayDateKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String? _buildCheckInSummary() {
    if (_selectedWorkout != null) {
      final session = _selectedWorkout!;
      final name = session.planName.trim().isNotEmpty
          ? session.planName.trim()
          : 'Buổi tập Saman';
      if (!_includeDetailedMetrics) {
        return 'Hoàn thành $name';
      }
      final parts = <String>[name];
      final durationSec = getSessionDurationSeconds(session);
      if (durationSec != null && durationSec >= 60) {
        parts.add('${(durationSec / 60).round()} phút');
      }
      final completedSets =
          session.exerciseLogs.where((l) => l.isCompleted).length;
      if (completedSets > 0) {
        parts.add('$completedSets hiệp');
      }
      if (session.totalVolumeKg > 0) {
        parts.add('${session.totalVolumeKg} kg');
      }
      return parts.join(' • ');
    }
    if (_selectedMeal != null) {
      final meal = _selectedMeal!;
      final food = meal.foodName.trim().isNotEmpty
          ? meal.foodName.trim()
          : 'Bữa ăn lành mạnh';
      final base = '${meal.mealType.displayName} • $food';
      if (!_includeDetailedMetrics) {
        return base;
      }
      final note = meal.note?.trim() ?? '';
      if (note.isNotEmpty) {
        return '$base • $note';
      }
      final hh = meal.loggedAt.hour.toString().padLeft(2, '0');
      final mm = meal.loggedAt.minute.toString().padLeft(2, '0');
      return '$base • $hh:$mm';
    }
    return null;
  }

  String? _buildCheckInTagLine() {
    final summary = _buildCheckInSummary();
    if (summary == null || summary.isEmpty) return null;
    if (_selectedWorkout != null) {
      return '[SAMAN_WORKOUT] $summary';
    }
    if (_selectedMeal != null) {
      return '[SAMAN_MEAL] $summary';
    }
    return null;
  }

  Color _parseHexColor(String hex, Color fallback) {
    final cleaned = hex.replaceFirst('#', '').trim();
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }

  String _inferMimeType(String filename, {required bool isVideo}) {
    final ext =
        filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    if (isVideo) {
      switch (ext) {
        case 'mov':
          return 'video/quicktime';
        case 'webm':
          return 'video/webm';
        case 'mkv':
          return 'video/x-matroska';
        case 'mp4':
        default:
          return 'video/mp4';
      }
    }
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedFile = file;
        _pickedBytes = bytes;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể chọn ảnh từ thư viện';
      });
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedFile = file;
        _pickedBytes = bytes;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể chọn video từ thư viện';
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final rawCaption = _captionController.text.trim();
    final checkInTag = _buildCheckInTagLine();
    final finalCaption = checkInTag != null
        ? (rawCaption.isNotEmpty ? '$checkInTag\n$rawCaption' : checkInTag)
        : rawCaption;

    if (_mediaType == 'text' && finalCaption.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập nội dung cho tin văn bản';
      });
      return;
    }
    if ((_mediaType == 'photo' || _mediaType == 'video') &&
        (_pickedFile == null || _pickedBytes == null)) {
      setState(() {
        _errorMessage = _mediaType == 'photo'
            ? 'Vui lòng chọn ảnh để đăng tin'
            : 'Vui lòng chọn video để đăng tin';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      String? uploadedMediaUrl;
      if (_mediaType == 'photo' &&
          _pickedFile != null &&
          _pickedBytes != null) {
        final filename =
            _pickedFile!.name.isNotEmpty ? _pickedFile!.name : 'story.jpg';
        final mimeType = _inferMimeType(filename, isVideo: false);
        final useRemote = ref.read(useRemoteCommunityProvider);
        if (useRemote) {
          final res =
              await ref.read(communityRemoteDatasourceProvider).uploadMedia(
                    bytes: _pickedBytes!,
                    filename: filename,
                    mimeType: mimeType,
                  );
          uploadedMediaUrl = res['media_url'] as String?;
        } else {
          final res =
              await ref.read(communityRepositoryProvider).uploadDmMedia(
                    bytes: _pickedBytes!,
                    filename: filename,
                    mimeType: mimeType,
                  );
          uploadedMediaUrl = res.mediaUrl;
        }
      } else if (_mediaType == 'video' &&
          _pickedFile != null &&
          _pickedBytes != null) {
        final filename =
            _pickedFile!.name.isNotEmpty ? _pickedFile!.name : 'story.mp4';
        final mimeType = _inferMimeType(filename, isVideo: true);
        final res = await ref.read(communityRepositoryProvider).uploadDmMedia(
              bytes: _pickedBytes!,
              filename: filename,
              mimeType: mimeType,
            );
        uploadedMediaUrl = res.mediaUrl;
      }

      if ((_mediaType == 'photo' || _mediaType == 'video') &&
          (uploadedMediaUrl == null || uploadedMediaUrl.trim().isEmpty)) {
        throw StateError('Không nhận được đường dẫn media sau khi tải lên');
      }

      final created =
          await ref.read(communityStoriesProvider.notifier).createStory(
                mediaType: _mediaType,
                mediaUrl: uploadedMediaUrl,
                caption: finalCaption,
                backgroundColor: _mediaType == 'text' ? _selectedBgHex : null,
                privacy: _privacy,
              );

      if (!mounted) return;
      if (created == null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Không thể đăng tin. Vui lòng thử lại.';
        });
        return;
      }
      Navigator.of(context).pop(created);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            'Đăng tin thất bại. Vui lòng kiểm tra kết nối và thử lại.';
      });
    }
  }

  void _selectMode(String mode) {
    if (_mediaType == mode || _isSubmitting) return;
    setState(() {
      _mediaType = mode;
      _pickedFile = null;
      _pickedBytes = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final checkInSummary = _buildCheckInSummary();
    final hasCheckIn = checkInSummary != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ig.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tạo tin 24h',
                    style: ig.displayTitle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ig.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      _isSubmitting ? null : () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(
                    minWidth: SamanIgTokens.minTouchTarget,
                    minHeight: SamanIgTokens.minTouchTarget,
                  ),
                  icon: Icon(Icons.close_rounded, color: ig.textSecondary),
                  tooltip: 'Đóng',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ModeSelectorRow(
              selectedMode: _mediaType,
              ig: ig,
              onSelect: _selectMode,
            ),
            const SizedBox(height: 16),
            if (_mediaType == 'text') ...[
              _TextStoryPreview(
                ig: ig,
                backgroundColor:
                    _parseHexColor(_selectedBgHex, ig.primaryAction),
                caption: _captionController.text,
                checkInSummary: checkInSummary,
                isWorkoutCheckIn: _selectedWorkout != null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Màu nền',
                    style: ig.caption(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ig.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _bgHexPresets.map((hex) {
                        final selected = hex == _selectedBgHex;
                        return GestureDetector(
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() => _selectedBgHex = hex),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: SamanIgTokens.minTouchTarget,
                            height: SamanIgTokens.minTouchTarget,
                            child: Center(
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: _parseHexColor(hex, ig.primaryAction),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? ig.primaryAction
                                        : ig.border,
                                    width: selected ? 2.5 : 1,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else if (_mediaType == 'photo') ...[
              _MediaPickerBox(
                ig: ig,
                icon: Icons.add_photo_alternate_outlined,
                emptyLabel: 'Chọn ảnh từ thư viện',
                pickedFileName: _pickedFile?.name,
                previewBytes: _pickedBytes,
                isVideo: false,
                onTap: _isSubmitting ? null : _pickPhoto,
              ),
              const SizedBox(height: 12),
            ] else ...[
              _MediaPickerBox(
                ig: ig,
                icon: Icons.video_library_outlined,
                emptyLabel: 'Chọn video ngắn (tối đa 30 giây)',
                pickedFileName: _pickedFile?.name,
                previewBytes: null,
                isVideo: true,
                fileSizeBytes: _pickedBytes?.length,
                onTap: _isSubmitting ? null : _pickVideo,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _captionController,
              enabled: !_isSubmitting,
              maxLength: 500,
              maxLines: _mediaType == 'text' ? 3 : 2,
              onChanged: (_) {
                if (_mediaType == 'text' || _errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              style: ig.body(
                color: ig.textPrimary,
                fontSize: 14,
              ),
              decoration: ig
                  .inputDecoration(
                    hintText: _mediaType == 'text'
                        ? 'Nhập nội dung tin của bạn...'
                        : 'Thêm chú thích (tùy chọn)...',
                    borderRadius: 12,
                  )
                  .copyWith(
                    counterStyle: ig.caption(
                      color: ig.textMuted,
                      fontSize: 11,
                    ).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
            ),
            const SizedBox(height: 8),
            // Optional Saman Check-in Sticker Section (Privacy-by-Design)
            Container(
              decoration: BoxDecoration(
                color: ig.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasCheckIn ? ig.primaryAction : ig.border,
                  width: hasCheckIn ? 1.2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _isSubmitting
                        ? null
                        : () => setState(
                              () => _showSamanCheckIn = !_showSamanCheckIn,
                            ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SamanIgTokens.storyGradient,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.bolt_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Chia sẻ Check-in Saman',
                                  style: ig.username(
                                    color: ig.textPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  hasCheckIn
                                      ? checkInSummary
                                      : 'Đính kèm sticker Buổi tập / Bữa ăn',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ig.caption(
                                    color: hasCheckIn
                                        ? ig.primaryAction
                                        : ig.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: hasCheckIn
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (hasCheckIn)
                            IconButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => setState(() {
                                        _selectedWorkout = null;
                                        _selectedMeal = null;
                                        _includeDetailedMetrics = false;
                                      }),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: ig.textSecondary,
                              ),
                              tooltip: 'Bỏ sticker',
                            ),
                          Icon(
                            _showSamanCheckIn
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: ig.textSecondary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showSamanCheckIn)
                    _SamanCheckInPickerSection(
                      ig: ig,
                      todayKey: _todayDateKey(),
                      selectedWorkout: _selectedWorkout,
                      selectedMeal: _selectedMeal,
                      includeDetailedMetrics: _includeDetailedMetrics,
                      isSubmitting: _isSubmitting,
                      onSelectWorkout: (session) {
                        setState(() {
                          if (_selectedWorkout?.id == session.id) {
                            _selectedWorkout = null;
                          } else {
                            _selectedWorkout = session;
                            _selectedMeal = null;
                          }
                          _errorMessage = null;
                        });
                      },
                      onSelectMeal: (meal) {
                        setState(() {
                          if (_selectedMeal?.id == meal.id) {
                            _selectedMeal = null;
                          } else {
                            _selectedMeal = meal;
                            _selectedWorkout = null;
                          }
                          _errorMessage = null;
                        });
                      },
                      onToggleDetails: (value) {
                        setState(() => _includeDetailedMetrics = value);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Quyền xem',
                  style: ig.caption(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ig.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PrivacyChip(
                        label: 'Công khai',
                        icon: Icons.public_rounded,
                        selected: _privacy == 'public',
                        ig: ig,
                        onTap: _isSubmitting
                            ? null
                            : () => setState(() => _privacy = 'public'),
                      ),
                      _PrivacyChip(
                        label: 'Người theo dõi',
                        icon: Icons.group_outlined,
                        selected: _privacy == 'followers_only',
                        ig: ig,
                        onTap: _isSubmitting
                            ? null
                            : () => setState(() => _privacy = 'followers_only'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ig.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: ig.danger.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: ig.caption(
                    color: ig.danger,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ig
                    .primaryButtonStyle(minHeight: 48, borderRadius: 12)
                    .copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.disabled)
                            ? ig.primaryAction.withOpacity(0.5)
                            : ig.primaryAction,
                      ),
                    ),
                child: _isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ig.onPrimaryAction,
                        ),
                      )
                    : Text(
                        'Đăng tin',
                        style: ig.buttonLabel(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ig.onPrimaryAction,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SamanCheckInPickerSection extends ConsumerWidget {
  const _SamanCheckInPickerSection({
    required this.ig,
    required this.todayKey,
    required this.selectedWorkout,
    required this.selectedMeal,
    required this.includeDetailedMetrics,
    required this.isSubmitting,
    required this.onSelectWorkout,
    required this.onSelectMeal,
    required this.onToggleDetails,
  });

  final SamanIgTokens ig;
  final String todayKey;
  final WorkoutSession? selectedWorkout;
  final MealLog? selectedMeal;
  final bool includeDetailedMetrics;
  final bool isSubmitting;
  final ValueChanged<WorkoutSession> onSelectWorkout;
  final ValueChanged<MealLog> onSelectMeal;
  final ValueChanged<bool> onToggleDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutsAsync = ref.watch(workoutHistoryProvider);
    final mealsAsync = ref.watch(dailyStoryControllerProvider(todayKey));

    final workouts = (workoutsAsync.valueOrNull ?? const <WorkoutSession>[])
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final recentWorkouts = workouts.take(3).toList();
    final recentMeals =
        (mealsAsync.valueOrNull ?? const <MealLog>[]).take(3).toList();
    final isLoading = workoutsAsync.isLoading &&
        mealsAsync.isLoading &&
        recentWorkouts.isEmpty &&
        recentMeals.isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ig.border, width: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
                  const SizedBox(width: 8),
                  Text(
                    'Đang tải hoạt động Saman gần đây...',
                    style: ig.caption(color: ig.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            )
          else if (recentWorkouts.isEmpty && recentMeals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Chưa có buổi tập hoặc bữa ăn gần đây để đính kèm.',
                style: ig.caption(color: ig.textSecondary, fontSize: 12),
              ),
            )
          else ...[
            if (recentWorkouts.isNotEmpty) ...[
              Text(
                'Buổi tập gần nhất',
                style: ig.caption(
                  color: ig.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recentWorkouts.map((session) {
                  final isSelected = selectedWorkout?.id == session.id;
                  final label = session.planName.trim().isNotEmpty
                      ? session.planName.trim()
                      : 'Buổi tập Saman';
                  return _CheckInOptionChip(
                    ig: ig,
                    icon: Icons.fitness_center_rounded,
                    label: label,
                    selected: isSelected,
                    onTap: isSubmitting ? null : () => onSelectWorkout(session),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
            if (recentMeals.isNotEmpty) ...[
              Text(
                'Bữa ăn hôm nay',
                style: ig.caption(
                  color: ig.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recentMeals.map((meal) {
                  final isSelected = selectedMeal?.id == meal.id;
                  final label = '${meal.mealType.displayName} • ${meal.foodName}';
                  return _CheckInOptionChip(
                    ig: ig,
                    icon: Icons.restaurant_rounded,
                    label: label,
                    selected: isSelected,
                    onTap: isSubmitting ? null : () => onSelectMeal(meal),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
          ],
          if (selectedWorkout != null || selectedMeal != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ig.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ig.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hiển thị chỉ số chi tiết',
                          style: ig.caption(
                            color: ig.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Mặc định ẩn số tạ, số hiệp và calo/ghi chú',
                          style: ig.caption(
                            color: ig.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: includeDetailedMetrics,
                    activeColor: ig.primaryAction,
                    onChanged: isSubmitting ? null : onToggleDetails,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckInOptionChip extends StatelessWidget {
  const _CheckInOptionChip({
    required this.ig,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SamanIgTokens ig;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? ig.primaryAction.withOpacity(0.14) : ig.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? ig.primaryAction : ig.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? ig.primaryAction : ig.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ig.caption(
                  color: selected ? ig.primaryAction : ig.textPrimary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSelectorRow extends StatelessWidget {
  const _ModeSelectorRow({
    required this.selectedMode,
    required this.ig,
    required this.onSelect,
  });

  final String selectedMode;
  final SamanIgTokens ig;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ig.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border),
      ),
      child: Row(
        children: [
          _ModeTab(
            label: 'Văn bản',
            icon: Icons.text_fields_rounded,
            selected: selectedMode == 'text',
            ig: ig,
            onTap: () => onSelect('text'),
          ),
          _ModeTab(
            label: 'Ảnh',
            icon: Icons.image_outlined,
            selected: selectedMode == 'photo',
            ig: ig,
            onTap: () => onSelect('photo'),
          ),
          _ModeTab(
            label: 'Video',
            icon: Icons.videocam_outlined,
            selected: selectedMode == 'video',
            ig: ig,
            onTap: () => onSelect('video'),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.ig,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final SamanIgTokens ig;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? ig.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: selected ? Border.all(color: ig.border) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? ig.primaryAction : ig.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ig.caption(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? ig.textPrimary : ig.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextStoryPreview extends StatelessWidget {
  const _TextStoryPreview({
    required this.ig,
    required this.backgroundColor,
    required this.caption,
    this.checkInSummary,
    this.isWorkoutCheckIn = true,
  });

  final SamanIgTokens ig;
  final Color backgroundColor;
  final String caption;
  final String? checkInSummary;
  final bool isWorkoutCheckIn;

  @override
  Widget build(BuildContext context) {
    final trimmed = caption.trim();
    final displayText = trimmed.isEmpty && checkInSummary == null
        ? 'Xem trước tin văn bản của bạn'
        : trimmed;
    return Container(
      height: 156,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (checkInSummary != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isWorkoutCheckIn
                        ? Icons.fitness_center_rounded
                        : Icons.restaurant_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      checkInSummary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ig.caption(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (displayText.isNotEmpty) const SizedBox(height: 10),
          ],
          if (displayText.isNotEmpty)
            Text(
              displayText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ig.displayTitle(
                color: trimmed.isEmpty
                    ? Colors.white.withOpacity(0.72)
                    : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ).copyWith(height: 1.35),
            ),
        ],
      ),
    );
  }
}

class _MediaPickerBox extends StatelessWidget {
  const _MediaPickerBox({
    required this.ig,
    required this.icon,
    required this.emptyLabel,
    required this.pickedFileName,
    required this.previewBytes,
    required this.isVideo,
    this.fileSizeBytes,
    required this.onTap,
  });

  final SamanIgTokens ig;
  final IconData icon;
  final String emptyLabel;
  final String? pickedFileName;
  final Uint8List? previewBytes;
  final bool isVideo;
  final int? fileSizeBytes;
  final VoidCallback? onTap;

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: ig.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ig.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: previewBytes != null && !isVideo
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(previewBytes!, fit: BoxFit.cover),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Đổi ảnh',
                        style: ig.caption(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    pickedFileName != null && isVideo
                        ? Icons.video_file_rounded
                        : icon,
                    size: 36,
                    color: pickedFileName != null
                        ? ig.primaryAction
                        : ig.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      pickedFileName ?? emptyLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ig.username(
                        color: pickedFileName != null
                            ? ig.textPrimary
                            : ig.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isVideo && fileSizeBytes != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_formatSize(fileSizeBytes!)} • Chạm để đổi video',
                      style: ig.caption(
                        color: ig.textMuted,
                        fontSize: 11.5,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _PrivacyChip extends StatelessWidget {
  const _PrivacyChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.ig,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final SamanIgTokens ig;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? ig.primaryAction.withOpacity(0.14)
              : ig.surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? ig.primaryAction : ig.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? ig.primaryAction : ig.textSecondary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ig.caption(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? ig.primaryAction : ig.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
