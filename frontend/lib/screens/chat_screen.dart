import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../controllers/chat_controller.dart';
import '../providers/daily_story_provider.dart';
import 'chat/tokens/saman_chat_tokens.dart';
import 'chat/widgets/widgets.dart';
import 'food_log_screen.dart';
import 'nutrition/widgets/meal_review_dialog.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? initialMessage;

  const ChatScreen({super.key, this.initialMessage});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null) {
      _textController.text = widget.initialMessage!;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);

    _scrollToBottom();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: SamanChatTokens.canvas,
      drawerScrimColor: SamanChatTokens.drawerScrim,
      drawer: SamanChatDrawer(
        onNewChat: () =>
            ref.read(chatControllerProvider.notifier).clearChat(),
        onPromptSelected: _handlePromptSelected,
        onOpenPreferences: _showPersonaDialog,
      ),
      appBar: SamanChatHeader(
        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
        onNewChat: () =>
            ref.read(chatControllerProvider.notifier).clearChat(),
      ),
      body: Column(
        children: [
          Expanded(
            child: (chatState.messages.isEmpty && chatState.foodAnalysisState == null)
                ? SamanChatEmptyState(
                    onPromptSelected: _handlePromptSelected,
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
                  ),
          ),
          _buildComposerArea(
            isLoading: chatState.isLoading,
            isAnalyzingFood: chatState.foodAnalysisState?.status ==
                FoodAnalysisStatus.analyzing,
            isEmptyState: chatState.messages.isEmpty &&
                chatState.foodAnalysisState == null,
          ),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---

  void _handlePromptSelected(String prompt) {
    ref.read(chatControllerProvider.notifier).sendMessage(prompt);
  }

  Widget _buildComposerArea({
    required bool isLoading,
    required bool isAnalyzingFood,
    required bool isEmptyState,
  }) {
    final isBusy = isLoading || isAnalyzingFood;

    return Container(
      color: SamanChatTokens.canvas,
      padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
      child: SafeArea(
        top: false,
        bottom: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEmptyState && !isBusy) ...[
                SamanChatRapidChips(
                  onChipSelected: _handlePromptSelected,
                ),
                const SizedBox(height: 8.0),
              ],
              SamanChatComposer(
                controller: _textController,
                onSend: _handleSend,
                isLoading: isBusy,
                loadingHintText: isAnalyzingFood
                    ? 'Saman is looking at your meal...'
                    : 'Saman is responding...',
                onAttachmentTap: _handleAttachmentFlow,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    ref.read(chatControllerProvider.notifier).sendMessage(text);
  }

  void _handleRetry() {
    ref.read(chatControllerProvider.notifier).retry();
  }

  void _handleEditQuestion() {
    final chatState = ref.read(chatControllerProvider);
    final failedText = chatState.failedUserMessage ??
        (chatState.messages.isNotEmpty && chatState.messages.last.role == 'user'
            ? chatState.messages.last.content
            : null);
    if (failedText != null) {
      _textController.text = failedText;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: failedText.length),
      );
    }
    ref.read(chatControllerProvider.notifier).clearError();
  }

  Future<void> _handleAttachmentFlow() async {
    final source = await SamanAttachmentSheet.show(context);
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (picked != null && mounted) {
      ref.read(chatControllerProvider.notifier).analyzeFoodPhoto(picked);
    }
  }

  Future<void> _handleLogMeal() async {
    final foodState = ref.read(chatControllerProvider).foodAnalysisState;
    if (foodState?.result == null) return;

    final confirmed = await MealReviewDialog.show(context, foodState!.result!);
    if (confirmed != null && mounted) {
      try {
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        await ref
            .read(dailyStoryControllerProvider(todayStr).notifier)
            .confirmLog(confirmed, imageFile: foodState.imageFile);

        ref.read(chatControllerProvider.notifier).markMealLogged();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Meal logged successfully!'),
              backgroundColor: SamanChatTokens.surfaceElevated,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to log meal: $e'),
              backgroundColor: SamanChatTokens.surfaceElevated,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _handleManualMealEntry() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FoodLogScreen(),
      ),
    );
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
    showModalBottomSheet(
      context: context,
      backgroundColor: SamanChatTokens.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saman Preferences',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: SamanChatTokens.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Coaching tone & response style',
                  style: TextStyle(
                    fontSize: 12,
                    color: SamanChatTokens.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildPersonaOption("🏋️‍♂️", "Strict PT",
                    "Disciplined, performance-focused, no excuses.", """
From now on, act as a STRICT Personal Trainer.
Be disciplined, direct, and performance-oriented.
Use firm and commanding language.
Do not accept excuses, laziness, or shortcuts.
Focus only on actions, consistency, and measurable results.
Avoid emotional encouragement; enforce accountability.
"""),
                _buildPersonaOption("👩‍⚕️", "Nutrition Doctor",
                    "Scientific, calm, and explanatory.", """
From now on, act as a Nutrition Specialist.
Base all advice strictly on scientific and evidence-based principles.
Use a calm, gentle, and professional tone.
Explain concepts clearly and logically when needed.
Prioritize health, safety, and long-term sustainability.
Avoid harsh or pressuring language.
"""),
                _buildPersonaOption("🤖", "AI Best Friend",
                    "Friendly, supportive, and motivating.", """
From now on, act as a supportive AI best friend.
Use a friendly, casual, and positive tone.
Be empathetic and encouraging.
Keep the conversation light and engaging.
Motivate through emotional support rather than strict discipline.
"""),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPersonaOption(
      String emoji, String name, String desc, String prompt) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () {
        Navigator.pop(context);
        ref.read(chatControllerProvider.notifier).sendMessage(prompt);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: SamanChatTokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: SamanChatTokens.borderSubtle),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SamanChatTokens.textWhite,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SamanChatTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: SamanChatTokens.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}
