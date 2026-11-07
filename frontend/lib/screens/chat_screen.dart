import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../config/app_translations.dart';
import '../controllers/chat_controller.dart';
import '../providers/daily_story_provider.dart';
import '../services/nutrition_service.dart';
import 'chat/tokens/saman_chat_tokens.dart';
import 'chat/widgets/history_analytics_sheet.dart';
import 'chat/widgets/widgets.dart';
import 'food_log_screen.dart';
import 'main_screen.dart';
import 'nutrition/widgets/meal_review_dialog.dart';
import '../data/models/exercise.dart';
import '../presentation/providers/exercise_providers.dart';
import '../presentation/screens/active_workout_screen.dart';
import '../presentation/providers/active_workout_providers.dart';
import '../features/workout/domain/entities/workout_plan.dart';
import '../features/workout/data/repositories/workout_repository_impl.dart';
import '../services/api_client.dart';
import '../widgets/saman_feedback_snackbar.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? initialMessage;
  final SamanNudge? initialNudge;
  final bool? isTabActive;

  const ChatScreen({
    super.key,
    this.initialMessage,
    this.initialNudge,
    this.isTabActive,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  SamanNudge? _activeNudge;
  bool _isLoggingMeal = false;
  bool _isDesktopSidebarExpanded = true;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _activeNudge = widget.initialNudge;
    if (widget.initialMessage != null) {
      _textController.text = widget.initialMessage!;
    }
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatControllerProvider.notifier).loadConversations(loadLatest: true);
      _handleScroll();
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final isScrolledUp = (position.maxScrollExtent - position.pixels) > 120.0;
    if (isScrolledUp != _showScrollToBottom) {
      if (mounted) {
        setState(() {
          _showScrollToBottom = isScrolledUp;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _composerFocusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleNudgePrimary(SamanNudge nudge) {
    setState(() {
      _activeNudge = null;
    });
    if (nudge.onPrimary != null) {
      nudge.onPrimary!();
    } else {
      final prompt = nudge.promptToSend ??
          'Plan a high-protein dinner based on my remaining nutrition targets.';
      _handlePromptSelected(prompt);
    }
  }

  void _handleNudgeSecondary(SamanNudge nudge) {
    setState(() {
      _activeNudge = null;
    });
    nudge.onSecondary?.call();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);

    _scrollToBottom();

    final hasNudge = _activeNudge != null;

    final route = ModalRoute.of(context);
    final isCurrentRoute = route?.isCurrent ?? true;
    final isRoot = route?.isFirst ?? true;
    final currentTabIndex = ref.watch(mainNavIndexProvider);
    final isChatActive = widget.isTabActive ??
        ((!isRoot || currentTabIndex == 2) && isCurrentRoute);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 840.0;

    final sidebarWidget = SamanChatDrawer(
      isDesktop: isDesktop,
      isExpanded: _isDesktopSidebarExpanded,
      onToggleExpand: () {
        setState(() {
          _isDesktopSidebarExpanded = !_isDesktopSidebarExpanded;
        });
      },
      onNewChat: () {
        setState(() {
          _activeNudge = null;
        });
        ref.read(chatControllerProvider.notifier).newConversation();
      },
      onPromptSelected: _handlePromptSelected,
      onOpenPreferences: _showPersonaDialog,
      onOpenAnalytics: _handleOpenAnalytics,
      onAttachFoodPhoto: _handleAttachmentFlow,
      hasActiveReminders: hasNudge,
      recentConversations: chatState.recentConversations,
      activeConversationId: chatState.activeConversationId,
      onSelectConversation: (id) {
        setState(() {
          _activeNudge = null;
        });
        ref.read(chatControllerProvider.notifier).loadConversation(id);
      },
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: SamanAuroraTokens.baseBackground,
      drawerScrimColor: SamanChatTokens.drawerScrim,
      drawer: isDesktop ? null : sidebarWidget,
      appBar: SamanChatHeader(
        showLeadingMenu: !isDesktop,
        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
        onNewChat: () {
          setState(() {
            _activeNudge = null;
          });
          ref.read(chatControllerProvider.notifier).newConversation();
        },
        hasActiveReminders: hasNudge,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop) sidebarWidget,
          Expanded(
            child: Column(
        children: [
          Expanded(
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: SamanChatBackground(
                      hasConversation: chatState.messages.isNotEmpty ||
                          chatState.foodAnalysisState != null ||
                          hasNudge,
                      isActive: isChatActive,
                    ),
                  ),
                  (chatState.messages.isEmpty &&
                          chatState.foodAnalysisState == null &&
                          !hasNudge)
                      ? SamanChatEmptyState(
                          onPromptSelected: _handleSuggestionSelected,
                        )
                      : SamanMessageList(
                          messages: chatState.messages,
                          scrollController: _scrollController,
                          isLoading: chatState.isLoading,
                          errorMessage: chatState.errorMessage,
                          onRetry: _handleRetry,
                          onEditQuestion: _handleEditQuestion,
                          foodAnalysisState: chatState.foodAnalysisState,
                          onLogMeal: _handleLogMeal,
                          onRetakeFoodPhoto: _handleAttachmentFlow,
                          onManualMealEntry: _handleManualMealEntry,
                          latestAssistantActions: _buildAssistantActions(chatState),
                          activeNudge: hasNudge
                              ? _activeNudge!.copyWith(
                                  onPrimary: () => _handleNudgePrimary(_activeNudge!),
                                  onSecondary: () =>
                                      _handleNudgeSecondary(_activeNudge!),
                                )
                              : null,
                        ),
                  Positioned(
                    right: 16.0,
                    bottom: 8.0,
                    child: AnimatedSwitcher(
                      duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: (_showScrollToBottom && chatState.messages.isNotEmpty)
                          ? Semantics(
                              key: const ValueKey('scroll_to_newest_button'),
                              button: true,
                              label: context.tr('scroll_to_newest'),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _scrollToNewest,
                                  borderRadius: BorderRadius.circular(20.0),
                                  hoverColor: SamanChatTokens.actionRowHoverBg,
                                  focusColor: SamanChatTokens.actionRowFocusBg,
                                  highlightColor: SamanChatTokens.actionRowPressedBg,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 11.0, vertical: 7.0),
                                    decoration: BoxDecoration(
                                      color: SamanChatTokens.surfaceElevated,
                                      borderRadius: BorderRadius.circular(20.0),
                                      border: Border.all(
                                        color: SamanChatTokens.borderSubtle,
                                        width: 1.0,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x4D000000),
                                          blurRadius: 8.0,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.arrow_downward_rounded,
                                          size: 14.0,
                                          color: SamanChatTokens.textWhite,
                                        ),
                                        const SizedBox(width: 4.0),
                                        Text(
                                          context.tr('newest_label'),
                                          style: const TextStyle(
                                            fontSize: 12.0,
                                            fontWeight: FontWeight.w600,
                                            color: SamanChatTokens.textWhite,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('scroll_to_newest_empty')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildComposerArea(
            isLoading: chatState.isLoading,
            isAnalyzingFood: chatState.foodAnalysisState?.status ==
                FoodAnalysisStatus.analyzing,
            isEmptyState: chatState.messages.isEmpty &&
                chatState.foodAnalysisState == null &&
                !hasNudge,
          ),
        ],
      ),
    ),
  ],
),
    );
  }

  // --- UI COMPONENTS ---

  List<SamanAssistantAction>? _buildAssistantActions(ChatState chatState) {
    final action = chatState.pendingAction;
    if (action == null || action['status'] != 'pending') return null;

    final type = action['type']?.toString();
    final actionId = action['id']?.toString() ?? '';
    final convId = chatState.activeConversationId ?? '';

    final List<dynamic>? rawActions =
        action['actions'] is List ? action['actions'] as List : null;
    if (rawActions != null && rawActions.isNotEmpty) {
      final List<SamanAssistantAction> buttons = [];
      for (final a in rawActions) {
        if (a is! Map) continue;
        final aType = a['type']?.toString();
        final aLabel = a['label']?.toString();
        List<String> exerciseIds = [];
        if (a['payload'] is Map && a['payload']['exercise_ids'] is List) {
          exerciseIds = (a['payload']['exercise_ids'] as List)
              .map((e) => e.toString())
              .toList();
        } else if (a['exercise_ids'] is List) {
          exerciseIds = (a['exercise_ids'] as List)
              .map((e) => e.toString())
              .toList();
        }

        if (aType == 'preview_workout') {
          buttons.add(
            SamanAssistantAction(
              label: aLabel ?? context.tr('preview_workout'),
              icon: Icons.fitness_center_rounded,
              isPrimary: true,
              onTap: () {
                _handlePreviewWorkout(exerciseIds);
              },
            ),
          );
        } else if (aType == 'save_plan') {
          buttons.add(
            SamanAssistantAction(
              label: aLabel ?? context.tr('save_as_plan'),
              icon: Icons.save,
              isPrimary: false,
              onTap: () {
                _handleSavePlan(exerciseIds);
              },
            ),
          );
        } else if (aType == 'save_preference') {
          Map<String, dynamic> prefs = {};
          if (a['payload'] is Map && a['payload']['preferences'] is Map) {
            prefs = Map<String, dynamic>.from(a['payload']['preferences'] as Map);
          } else if (a['preferences'] is Map) {
            prefs = Map<String, dynamic>.from(a['preferences'] as Map);
          }
          buttons.add(
            SamanAssistantAction(
              label: aLabel ?? context.tr('save_preference_default'),
              icon: Icons.bookmark,
              isPrimary: false,
              onTap: () {
                _handleSavePreference(prefs);
              },
            ),
          );
        }
      }
      if (buttons.isNotEmpty) {
        return buttons;
      }
    }

    if (type == 'preview_workout') {
      final label = action['label']?.toString() ?? context.tr('preview_workout');
      List<String> exerciseIds = [];
      if (action['payload'] is Map && action['payload']['exercise_ids'] is List) {
        exerciseIds = (action['payload']['exercise_ids'] as List)
            .map((e) => e.toString())
            .toList();
      } else if (action['exercise_ids'] is List) {
        exerciseIds = (action['exercise_ids'] as List)
            .map((e) => e.toString())
            .toList();
      }

      return [
        SamanAssistantAction(
          label: label,
          icon: Icons.fitness_center_rounded,
          isPrimary: true,
          onTap: () {
            _handlePreviewWorkout(exerciseIds);
          },
        ),
      ];
    }

    if (type == 'save_plan') {
      final label = action['label']?.toString() ?? context.tr('save_as_plan');
      List<String> exerciseIds = [];
      if (action['payload'] is Map && action['payload']['exercise_ids'] is List) {
        exerciseIds = (action['payload']['exercise_ids'] as List)
            .map((e) => e.toString())
            .toList();
      } else if (action['exercise_ids'] is List) {
        exerciseIds = (action['exercise_ids'] as List)
            .map((e) => e.toString())
            .toList();
      }

      return [
        SamanAssistantAction(
          label: label,
          icon: Icons.save,
          isPrimary: true,
          onTap: () {
            _handleSavePlan(exerciseIds);
          },
        ),
      ];
    }

    if (type == 'save_preference') {
      final label = action['label']?.toString() ?? context.tr('save_preference_default');
      Map<String, dynamic> prefs = {};
      if (action['payload'] is Map && action['payload']['preferences'] is Map) {
        prefs = Map<String, dynamic>.from(action['payload']['preferences'] as Map);
      } else if (action['preferences'] is Map) {
        prefs = Map<String, dynamic>.from(action['preferences'] as Map);
      }

      return [
        SamanAssistantAction(
          label: label,
          icon: Icons.bookmark,
          isPrimary: true,
          onTap: () {
            _handleSavePreference(prefs);
          },
        ),
      ];
    }

    String confirmLabel;
    if (type == 'log_water') {
      final amount = action['amount_ml'] ?? 250;
      confirmLabel = context.tr('confirm_log_water_format').replaceAll('{amount}', '$amount');
    } else if (type == 'log_meal') {
      final cals = action['total_calories'];
      final foods = action['foods'];
      String foodName = '';
      if (foods is List && foods.isNotEmpty && foods.first is Map) {
        foodName = foods.first['name']?.toString() ?? '';
      }
      if (foodName.isNotEmpty && cals != null) {
        confirmLabel = context.tr('confirm_log_meal_format').replaceAll('{food}', foodName).replaceAll('{cals}', '$cals');
      } else if (cals != null) {
        confirmLabel = context.tr('confirm_log_meal_cals_format').replaceAll('{cals}', '$cals');
      } else {
        confirmLabel = context.tr('confirm_log_meal_generic');
      }
    } else if (type == 'adjust_workout') {
      final planName = action['plan_name']?.toString() ?? context.tr('workout_plan');
      final changes = action['changes'] is Map
          ? action['changes'] as Map
          : (action['after'] is Map ? action['after'] as Map : null);
      String detail = '';
      if (changes != null && changes.containsKey('duration_minutes')) {
        detail = '${changes['duration_minutes']} min';
      } else if (changes != null && changes.containsKey('difficulty')) {
        detail = '${changes['difficulty']}';
      }
      if (detail.isNotEmpty) {
        confirmLabel = context.tr('confirm_adjust_workout_format').replaceAll('{plan}', planName).replaceAll('{detail}', detail);
      } else {
        confirmLabel = context.tr('confirm_adjust_workout_generic').replaceAll('{plan}', planName);
      }
    } else {
      confirmLabel = context.tr('confirm_action');
    }

    return [
      SamanAssistantAction(
        label: confirmLabel,
        icon: Icons.check_circle_outline,
        isPrimary: true,
        onTap: () {
          ref.read(chatControllerProvider.notifier).confirmAction(convId, actionId);
        },
      ),
      SamanAssistantAction(
        label: context.tr('cancel_action'),
        icon: Icons.close,
        isPrimary: false,
        onTap: () {
          ref.read(chatControllerProvider.notifier).cancelAction(convId, actionId);
        },
      ),
    ];
  }

  Future<void> _handlePreviewWorkout(List<String> exerciseIds) async {
    if (exerciseIds.isEmpty) return;

    List<Exercise> allExercises = [];
    try {
      allExercises = await ref.read(exerciseLibraryListProvider.future);
    } catch (_) {
      allExercises = curatedExerciseLibrary;
    }

    final targetExercises = <Exercise>[];
    for (final id in exerciseIds) {
      final normalized = id.trim().toLowerCase();
      final match = allExercises.firstWhere(
        (e) => e.id.toLowerCase() == normalized || e.slug.toLowerCase() == normalized,
        orElse: () => allExercises.firstWhere(
          (e) => e.name.toLowerCase() == normalized || e.nameVi.toLowerCase() == normalized,
          orElse: () => const Exercise(
            id: '',
            slug: '',
            name: '',
            nameVi: '',
            muscleGroup: '',
            difficulty: 'intermediate',
            thumbnailUrl: '',
            defaultSets: 3,
            defaultReps: '8-12',
            restSeconds: 60,
            repType: 'reps',
          ),
        ),
      );
      if (match.id.isNotEmpty) {
        targetExercises.add(match);
      }
    }

    if (!mounted) return;
    if (targetExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('no_exercise_details_found')),
        ),
      );
      return;
    }

    _showWorkoutPreviewModal(targetExercises);
  }

  Future<void> _handleSavePlan(List<String> exerciseIds) async {
    if (exerciseIds.isEmpty) return;

    List<Exercise> allExercises = [];
    try {
      allExercises = await ref.read(exerciseLibraryListProvider.future);
    } catch (_) {
      allExercises = curatedExerciseLibrary;
    }

    final targetExercises = <Exercise>[];
    for (final id in exerciseIds) {
      final normalized = id.trim().toLowerCase();
      final match = allExercises.firstWhere(
        (e) => e.id.toLowerCase() == normalized || e.slug.toLowerCase() == normalized,
        orElse: () => allExercises.firstWhere(
          (e) => e.name.toLowerCase() == normalized || e.nameVi.toLowerCase() == normalized,
          orElse: () => const Exercise(
            id: '',
            slug: '',
            name: '',
            nameVi: '',
            muscleGroup: '',
            difficulty: 'intermediate',
            thumbnailUrl: '',
            defaultSets: 3,
            defaultReps: '8-12',
            restSeconds: 60,
            repType: 'reps',
          ),
        ),
      );
      if (match.id.isNotEmpty) {
        targetExercises.add(match);
      }
    }

    if (!mounted) return;
    if (targetExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('no_exercises_to_save_plan')),
        ),
      );
      return;
    }

    final now = DateTime.now();
    final formattedTime =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final planName = 'AI Workout - $formattedTime';

    final category = targetExercises.first.muscleGroup.isNotEmpty
        ? targetExercises.first.muscleGroup
        : 'Full Body';
    final level = targetExercises.first.difficulty.isNotEmpty
        ? targetExercises.first.difficulty
        : 'Intermediate';

    final workoutExercises = targetExercises.map((e) {
      return WorkoutExercise(
        name: e.name.isNotEmpty ? e.name : e.nameVi,
        reps: e.defaultReps.isNotEmpty ? e.defaultReps : '10',
        setCount: e.defaultSets > 0 ? e.defaultSets : 3,
      );
    }).toList();

    final plan = WorkoutPlan(
      title: planName,
      category: category,
      level: level,
      duration: targetExercises.length * 10,
      kcal: targetExercises.length * 50,
      exercises: workoutExercises,
    );

    try {
      final repo = ref.read(workoutRepositoryProvider);
      await repo.createWorkoutPlan(plan);

      if (!mounted) return;
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('save_plan_success'),
        type: FeedbackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('save_plan_error').replaceAll('{error}', '$e'),
        type: FeedbackType.error,
      );
    }
  }

  Future<void> _handleSavePreference(Map<String, dynamic> preferences) async {
    if (preferences.isEmpty) return;

    try {
      await ApiClient.dio.put(
        '/api/user/update-profile',
        data: {'preferences': preferences},
      );

      if (!mounted) return;
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('save_preference_success'),
        type: FeedbackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('save_preference_error').replaceAll('{error}', '$e'),
        type: FeedbackType.error,
      );
    }
  }

  void _startWorkoutSession(BuildContext modalContext, List<Exercise> exercises) {
    final session = ref.read(activeWorkoutSessionProvider);
    final bool hasActiveSession = !session.isFinished &&
        (session.elapsedSeconds > 0 || session.completedSetsCount > 0);

    if (!hasActiveSession) {
      Navigator.of(modalContext).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActiveWorkoutScreen.fromExercises(
            exercises: exercises,
            title: 'AI Recommended Workout',
          ),
        ),
      );
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: SamanChatTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: SamanChatTokens.borderSubtle),
          ),
          title: Text(
            context.tr('ongoing_workout_title'),
            style: const TextStyle(
              color: SamanChatTokens.textWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            context.tr('ongoing_workout_content'),
            style: const TextStyle(
              color: SamanChatTokens.textSecondary,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                context.tr('cancel_action'),
                style: const TextStyle(color: SamanChatTokens.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: SamanChatTokens.greenAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(
                context.tr('agree_btn'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        ref.read(activeWorkoutSessionProvider.notifier).clearPendingSave();
        ref.read(activeWorkoutSessionProvider.notifier).markSaved();

        if (Navigator.of(modalContext).canPop()) {
          Navigator.of(modalContext).pop();
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ActiveWorkoutScreen.fromExercises(
              exercises: exercises,
              title: 'AI Recommended Workout',
            ),
          ),
        );
      }
    });
  }

  void _showWorkoutPreviewModal(List<Exercise> exercises) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SamanChatTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: SamanChatTokens.borderSubtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.fitness_center_rounded,
                      color: SamanChatTokens.greenAccent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('preview_workout_title_format').replaceAll('{count}', '${exercises.length}'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: SamanChatTokens.textWhite,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('preview_workout_description'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: SamanChatTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: exercises.length,
                    separatorBuilder: (_, __) => const Divider(
                      color: SamanChatTokens.borderSubtle,
                      height: 12,
                    ),
                    itemBuilder: (ctx, index) {
                      final ex = exercises[index];
                      final name = ex.nameVi.isNotEmpty ? ex.nameVi : ex.name;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: SamanChatTokens.greenAccent.withOpacity(0.15),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: SamanChatTokens.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            color: SamanChatTokens.textWhite,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${ex.muscleGroup} • ${ex.defaultSets} ${context.tr('unit_sets')} × ${ex.defaultReps}',
                          style: const TextStyle(
                            color: SamanChatTokens.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SamanChatTokens.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      _startWorkoutSession(modalContext, exercises);
                    },
                    child: Text(
                      context.tr('start_workout_now'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleOpenAnalytics() {
    final chatState = ref.read(chatControllerProvider);
    final isBusy = chatState.isLoading ||
        chatState.foodAnalysisState?.status == FoodAnalysisStatus.analyzing;
    if (isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('saman_responding_wait'))),
      );
      return;
    }
    HistoryAnalyticsSheet.show(context);
  }

  void _handlePromptSelected(String prompt) {
    final chatState = ref.read(chatControllerProvider);
    final isBusy = chatState.isLoading ||
        chatState.foodAnalysisState?.status == FoodAnalysisStatus.analyzing;
    if (isBusy) return;
    ref.read(chatControllerProvider.notifier).sendMessage(prompt);
  }

  void _handleSuggestionSelected(String prompt) {
    if (_textController.text.trim().isEmpty) {
      _textController.text = prompt;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    }
    _composerFocusNode.requestFocus();
  }

  Widget _buildComposerArea({
    required bool isLoading,
    required bool isAnalyzingFood,
    required bool isEmptyState,
  }) {
    final isBusy = isLoading || isAnalyzingFood;

    return Container(
      color: SamanAuroraTokens.baseBackground,
      padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
      child: SafeArea(
        top: false,
        bottom: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isEmptyState) ...[
                SamanChatActionRow(
                  item: SamanChatActionItem.approvedActions
                      .singleWhere((action) => action.opensAnalytics),
                  onTap: _handlePromptSelected,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (isEmptyState && !isBusy) ...[
                SamanChatRapidChips(
                  onChipSelected: _handleSuggestionSelected,
                ),
                const SizedBox(height: 8.0),
              ],
              SamanChatComposer(
                controller: _textController,
                focusNode: _composerFocusNode,
                onSend: _handleSend,
                isLoading: isBusy,
                loadingHintText: isAnalyzingFood
                    ? context.tr('saman_looking_at_meal')
                    : context.tr('saman_responding_hint'),
                onAttachFoodPhoto: _handleAttachmentFlow,
                onOpenAnalytics: _handleOpenAnalytics,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSend() {
    final chatState = ref.read(chatControllerProvider);
    final isBusy = chatState.isLoading ||
        chatState.foodAnalysisState?.status == FoodAnalysisStatus.analyzing;
    if (isBusy) return;

    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    ref.read(chatControllerProvider.notifier).sendMessage(text);
  }

  void _handleRetry() {
    final draft = _textController.value;
    ref.read(chatControllerProvider.notifier).retry();
    _textController.value = draft;
  }

  Future<void> _handleEditQuestion() async {
    final chatState = ref.read(chatControllerProvider);
    final failedText = chatState.failedUserMessage ??
        (chatState.messages.isNotEmpty && chatState.messages.last.role == 'user'
            ? chatState.messages.last.content
            : null);
    if (failedText == null) return;

    final currentDraft = _textController.text.trim();
    if (currentDraft.isNotEmpty && currentDraft != failedText) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: SamanChatTokens.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          title: Text(
            context.tr('replace_draft_title'),
            style: const TextStyle(color: SamanChatTokens.textWhite, fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
          content: Text(
            context.tr('replace_draft_content'),
            style: const TextStyle(color: SamanChatTokens.textSecondary, fontSize: 14.0),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(context.tr('keep_draft_btn'), style: const TextStyle(color: SamanChatTokens.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(context.tr('replace_btn'), style: const TextStyle(color: SamanChatTokens.greenAccent)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    _textController.text = failedText;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: failedText.length),
    );
    _composerFocusNode.requestFocus();
    ref.read(chatControllerProvider.notifier).clearError();
  }

  Future<void> _handleAttachmentFlow() async {
    final chatState = ref.read(chatControllerProvider);
    final isBusy = chatState.isLoading ||
        chatState.foodAnalysisState?.status == FoodAnalysisStatus.analyzing;
    if (isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('saman_responding_wait'))),
      );
      return;
    }

    final source = await SamanAttachmentSheet.show(context);
    if (source == null || !mounted) return;
    final guard = ref.read(nutritionSessionProvider);
    NutritionRequestContext owner;
    try { owner = await guard.capture(); }
    on NutritionSessionChanged { return; }
    if (!mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source.source,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (picked != null && mounted) {
      try { await owner.validate(); }
      on NutritionSessionChanged { return; }
      if (!mounted) return;
      ref.read(chatControllerProvider.notifier).analyzeFoodPhoto(picked, mode: source.mode);
    }
  }

  Future<void> _handleLogMeal() async {
    if (_isLoggingMeal) return;
    final foodState = ref.read(chatControllerProvider).foodAnalysisState;
    if (foodState?.result == null || foodState!.isMealLogged) return;
    _isLoggingMeal = true;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // Keep the originating autoDispose provider alive while its dialog is open.
    final subscription = ProviderScope.containerOf(context, listen: false)
        .listen(dailyStoryControllerProvider(todayStr), (_, __) {});
    try {
      final owner = foodState.owner ?? await ref.read(nutritionSessionProvider).capture();
      await owner.validate();
      if (!mounted) return;
      final controller = ref.read(dailyStoryControllerProvider(todayStr).notifier);
      final confirmed = await MealReviewDialog.show(
        context,
        foodState.result!,
        imageFile: foodState.imageFile,
        imagePath: foodState.imagePath,
        onConfirm: (data) async {
          await owner.validate();
          await controller.confirmLog(data, imageFile: foodState.imageFile, session: owner);
          await owner.validate();
        },
      );
      if (confirmed == null || !mounted) return;
      await owner.validate();
      if (!mounted) return;
      if (identical(ref.read(chatControllerProvider).foodAnalysisState, foodState)) {
        ref.read(chatControllerProvider.notifier).markMealLogged();
      }
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('meal_added_success'),
        type: FeedbackType.success,
      );
    } on NutritionSessionChanged {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(const NutritionSessionChanged().toString())));
      }
    } finally {
      subscription.close();
      _isLoggingMeal = false;
    }
  }

  void _handleManualMealEntry() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FoodLogScreen(),
      ),
    );
  }

  void _scrollToNewest() {
    if (!_scrollController.hasClients) return;
    setState(() => _showScrollToBottom = false);
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.pixels < _scrollController.position.maxScrollExtent) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels > 96) return;
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _showPersonaDialog() {
    // Preferences/Persona selection is anchored and handled directly via showCoachPersonaMenu in SamanChatDrawer
  }


}
