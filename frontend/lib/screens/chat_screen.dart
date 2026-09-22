import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../config/app_theme.dart';
import '../widgets/app_logo.dart';
import '../controllers/chat_controller.dart';

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

  final List<String> _quickSuggestions = [
    "🥗 Thực đơn giảm cân?",
    "💪 Bài tập bụng tại nhà",
    "😫 Đau lưng nên tập gì?",
    "🍎 Calo trong 1 quả táo?",
  ];

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
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    _scrollToBottom();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.bgColor,
      drawer: _buildModernDrawer(),
      appBar: AppBar(
        // 🔥 UPDATE: Title Branding
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 24, color: colors.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'AI Coach',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: context.bgColor,
        elevation: 0,
        leading: IconButton(
          icon:
              Icon(Icons.dashboard_customize_outlined, color: colors.onSurface),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.onSurface),
            onPressed: () =>
                ref.read(chatControllerProvider.notifier).clearChat(),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.xl,
                    ),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(chatState.messages[index]);
                    },
                  ),
          ),
          _buildInputArea(chatState.isLoading),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildEmptyState() {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final extension = Theme.of(context).extension<AppThemeExtension>()!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.trackColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: colors.outline),
              ),
              alignment: Alignment.center,
              child: AppLogo(size: 56, color: colors.primary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Your coach is ready',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ask about training, recovery, meals, or your next step.',
              style: textTheme.bodyMedium?.copyWith(color: extension.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 17,
                color: colors.onPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: isUser ? colors.primary : context.surfaceColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppRadius.lg),
                  topRight: const Radius.circular(AppRadius.lg),
                  bottomLeft:
                      Radius.circular(isUser ? AppRadius.lg : AppRadius.sm),
                  bottomRight:
                      Radius.circular(isUser ? AppRadius.sm : AppRadius.lg),
                ),
                border: isUser ? null : Border.all(color: colors.outline),
              ),
              child: isUser
                  ? Text(
                      msg.content,
                      style: textTheme.bodyLarge?.copyWith(
                        color: colors.onPrimary,
                        height: 1.45,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: msg.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: colors.onSurface,
                              fontSize: 15,
                              height: 1.5,
                            ),
                            strong: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                            tableBody: TextStyle(color: colors.onSurface),
                            tableHead: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                            tableBorder: TableBorder.all(color: colors.outline),
                          ),
                        ),
                        if (msg.isTyping)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: colors.primary)),
                          )
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(bool isLoading) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLoading)
              SizedBox(
                height: 50,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.sm,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: _quickSuggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return ActionChip(
                      label: Text(
                        _quickSuggestions[index],
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: context.trackColor,
                      side: BorderSide(color: colors.outline),
                      onPressed: () {
                        _textController.text = _quickSuggestions[index];
                        _handleSend();
                      },
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: colors.secondary,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text("Tính năng Gửi ảnh/Tool sẽ sớm ra mắt!")));
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Hỏi AI Coach...',
                        filled: true,
                        fillColor: context.trackColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          borderSide: BorderSide(color: colors.outline),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      enabled: !isLoading,
                      onSubmitted: isLoading ? null : (_) => _handleSend(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: isLoading ? null : _handleSend,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isLoading
                            ? colors.onSurface.withOpacity(0.12)
                            : colors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(
                        Icons.arrow_upward,
                        color: isLoading
                            ? colors.onSurface.withOpacity(0.38)
                            : colors.onPrimary,
                        size: 22,
                      ),
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

  // --- DRAWER (Giữ nguyên logic cũ, chỉ cập nhật Header Drawer nếu cần) ---
  Widget _buildModernDrawer() {
    final colors = Theme.of(context).colorScheme;
    final extension = Theme.of(context).extension<AppThemeExtension>()!;
    return Drawer(
      backgroundColor: context.insightCardColor,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: context.insightCardColor,
              border: Border(
                bottom: BorderSide(color: colors.onPrimary.withOpacity(0.12)),
              ),
            ),
            child: Row(
              children: [
                AppLogo(size: 50, color: colors.primary),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SAMAN',
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text("Premium Member",
                          style:
                              TextStyle(color: colors.primary, fontSize: 12)),
                    ],
                  ),
                )
              ],
            ),
          ),
          // ... (Phần còn lại của Drawer giữ nguyên)
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
                  color: extension.aiAccent,
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
    final extension = Theme.of(context).extension<AppThemeExtension>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: extension.labelCaps.copyWith(
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
