import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../controllers/chat_controller.dart';
import 'chat/tokens/saman_chat_tokens.dart';
import 'chat/widgets/widgets.dart';

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
      drawer: _buildModernDrawer(),
      appBar: SamanChatHeader(
        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
        onNewChat: () =>
            ref.read(chatControllerProvider.notifier).clearChat(),
      ),
      body: Column(
        children: [
          Expanded(
            child: chatState.messages.isEmpty
                ? SamanChatEmptyState(
                    onPromptSelected: _handlePromptSelected,
                  )
                : SamanMessageList(
                    messages: chatState.messages,
                    scrollController: _scrollController,
                  ),
          ),
          _buildComposerArea(chatState.isLoading, chatState.messages.isEmpty),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---

  void _handlePromptSelected(String prompt) {
    ref.read(chatControllerProvider.notifier).sendMessage(prompt);
  }

  Widget _buildComposerArea(bool isLoading, bool isEmptyState) {
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
              if (isEmptyState && !isLoading) ...[
                SamanChatRapidChips(
                  onChipSelected: _handlePromptSelected,
                ),
                const SizedBox(height: 8.0),
              ],
              SamanChatComposer(
                controller: _textController,
                onSend: _handleSend,
                isLoading: isLoading,
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

  // --- DRAWER ---
  Widget _buildModernDrawer() {
    final colors = Theme.of(context).colorScheme;
    final extension = Theme.of(context).extension<AppThemeExtension>();
    return Drawer(
      backgroundColor: const Color(0xFF111215),
      child: Column(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Color(0xFF111215),
              border: Border(
                bottom: BorderSide(color: SamanChatTokens.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                SamanMonogram(size: 40, borderRadius: 10, fontSize: 18),
                SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saman Coach',
                        style: TextStyle(
                          color: SamanChatTokens.textWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Adaptive AI',
                        style: TextStyle(
                          color: SamanChatTokens.greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              children: [
                _buildSectionTitle("QUẢN LÝ CHAT"),
                _buildDrawerItem(
                  icon: Icons.add_comment_rounded,
                  title: "Cuộc trò chuyện mới",
                  onTap: () {
                    ref.read(chatControllerProvider.notifier).clearChat();
                    Navigator.pop(context);
                  },
                ),
                Divider(color: colors.onPrimary.withOpacity(0.12), height: 30),
                _buildSectionTitle("PHÂN TÍCH & BÁO CÁO"),
                _buildDrawerItem(
                  icon: Icons.analytics_outlined,
                  title: "Phân tích 7 ngày qua",
                  subtitle: "Calo, Macro & Xu hướng",
                  color: colors.primary,
                  onTap: () {
                    _handlePromptAction(
                        "Dựa trên dữ liệu log ăn uống và tập luyện 7 ngày gần nhất của tôi mà bạn có, hãy phân tích chi tiết:\n1. Xu hướng calo (thừa hay thiếu?).\n2. Tỉ lệ Macro (Protein/Carb/Fat) đã ổn chưa?\n3. Đưa ra 3 lời khuyên cụ thể để cải thiện trong tuần tới.");
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.restaurant_menu,
                  title: "Gợi ý thực đơn hôm nay",
                  subtitle: "Dựa trên TDEE của tôi",
                  color: extension?.aiAccent ?? SamanChatTokens.greenAccent,
                  onTap: () {
                    _handlePromptAction(
                        "Hãy gợi ý cho tôi thực đơn chi tiết 3 bữa cho ngày hôm nay. Tính toán sao cho phù hợp với TDEE và mục tiêu cân nặng của tôi. Trình bày dạng bảng.");
                  },
                ),
                Divider(color: colors.onPrimary.withOpacity(0.12), height: 30),
                _buildSectionTitle("CÀI ĐẶT AI COACH"),
                _buildDrawerItem(
                  icon: Icons.psychology,
                  title: "Đổi tính cách Coach",
                  onTap: () => _showPersonaDialog(),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              "Version 2.1.0 (SAMAN OS)",
              style: TextStyle(
                color: colors.onPrimary.withOpacity(0.45),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ... (Các hàm helper _buildSectionTitle, _buildDrawerItem, _handlePromptAction, _showPersonaDialog, _buildPersonaOption giữ nguyên)
  Widget _buildSectionTitle(String title) {
    final colors = Theme.of(context).colorScheme;
    final extension = Theme.of(context).extension<AppThemeExtension>();
    final baseStyle = extension?.labelCaps ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: baseStyle.copyWith(
          color: colors.onPrimary.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
      {required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
      Color color = Colors.white}) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.onPrimary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: colors.onPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: colors.onPrimary.withOpacity(0.55),
                fontSize: 12,
              ),
            )
          : null,
      onTap: onTap,
      hoverColor: colors.onPrimary.withOpacity(0.08),
    );
  }

  void _handlePromptAction(String prompt) {
    Navigator.pop(context);
    ref.read(chatControllerProvider.notifier).sendMessage(prompt);
  }

  void _showPersonaDialog() {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                Text(
                  'Chọn phong cách huấn luyện',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
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
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
          color: context.trackColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.outline),
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
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    desc,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: colors.secondary, size: 14),
          ],
        ),
      ),
    );
  }
}
