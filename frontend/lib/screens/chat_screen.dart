import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/app_logo.dart'; // ✅ Import Logo SAMAN
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

  // Theme Colors
  final Color _bgWhite = const Color(0xFFF8F9FA);
  final Color _surfaceWhite = Colors.white;
  final Color _textBlack = const Color(0xFF1E1E1E);
  final Color _accentBlack = const Color(0xFF000000);

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
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);

    _scrollToBottom();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bgWhite,
      drawer: _buildModernDrawer(),
      appBar: AppBar(
        // 🔥 UPDATE: Title Branding
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 24, color: _textBlack),
            const SizedBox(width: 8),
            Text('SAMAN AI',
                style: TextStyle(
                    color: _textBlack,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0)),
          ],
        ),
        centerTitle: true,
        backgroundColor: _bgWhite,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.dashboard_customize_outlined, color: _textBlack),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: _textBlack),
            onPressed: () =>
                ref.read(chatControllerProvider.notifier).clearChat(),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyState() // 🔥 UPDATE: Màn hình chờ với Logo động
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 20),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🔥 Logo SAMAN động
          AppLogo(size: 100, color: _textBlack)
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.05, 1.05),
                  duration: 2000.ms,
                  curve: Curves.easeInOut)
              .shimmer(
                  delay: 2000.ms,
                  duration: 1500.ms,
                  color: Colors.grey.shade300),

          const SizedBox(height: 24),

          Text("SAMAN AI COACH",
                  style: TextStyle(
                      color: _textBlack,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2))
              .animate()
              .fadeIn()
              .slideY(begin: 0.2, end: 0),

          const SizedBox(height: 8),

          Text("Solid Body. Balanced Mind.",
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14))
              .animate()
              .fadeIn(delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    // ... (Giữ nguyên code cũ)
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // Thay icon robot bằng logo nhỏ nếu thích, ở đây giữ icon robot cho rõ ngữ cảnh
            CircleAvatar(
                radius: 16,
                backgroundColor: _accentBlack,
                child: const Icon(Icons.smart_toy_outlined,
                    size: 16, color: Colors.white)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser ? _accentBlack : _surfaceWhite,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                border: isUser ? null : Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child: isUser
                  ? Text(msg.content,
                      style: const TextStyle(color: Colors.white, fontSize: 15))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: msg.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                                color: _textBlack, fontSize: 15, height: 1.5),
                            strong: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent),
                            tableBody: TextStyle(color: _textBlack),
                            tableHead:
                                const TextStyle(fontWeight: FontWeight.bold),
                            tableBorder:
                                TableBorder.all(color: Colors.grey.shade300),
                          ),
                        ),
                        if (msg.isTyping)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _textBlack)),
                          )
                      ],
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildInputArea(bool isLoading) {
    // ... (Giữ nguyên code cũ)
    return Container(
      decoration: BoxDecoration(
        color: _surfaceWhite,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -4))
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLoading)
              SizedBox(
                height: 50,
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: _quickSuggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return ActionChip(
                      label: Text(_quickSuggestions[index],
                          style: TextStyle(color: _textBlack, fontSize: 12)),
                      backgroundColor: _bgWhite,
                      onPressed: () {
                        _textController.text = _quickSuggestions[index];
                        _handleSend();
                      },
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.grey),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text("Tính năng Gửi ảnh/Tool sẽ sớm ra mắt!")));
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: TextStyle(color: _textBlack),
                      decoration: InputDecoration(
                        hintText: 'Hỏi AI Coach...',
                        filled: true,
                        fillColor: _bgWhite,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _handleSend(),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: _accentBlack,
                      child: const Icon(Icons.arrow_upward,
                          color: Colors.white, size: 24),
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
    final text = _textController.text;
    if (text.isEmpty) return;
    _textController.clear();
    ref.read(chatControllerProvider.notifier).sendMessage(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // --- DRAWER (Giữ nguyên logic cũ, chỉ cập nhật Header Drawer nếu cần) ---
  Widget _buildModernDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                const AppLogo(
                    size: 50, color: Colors.white), // 🔥 Drawer dùng Logo SAMAN
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("SAMAN",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2)),
                      Text("Premium Member",
                          style: TextStyle(
                              color: Colors.greenAccent.shade400,
                              fontSize: 12)),
                    ],
                  ),
                )
              ],
            ),
          ),
          // ... (Phần còn lại của Drawer giữ nguyên)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
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
                const Divider(color: Colors.white10, height: 30),
                _buildSectionTitle("PHÂN TÍCH & BÁO CÁO"),
                _buildDrawerItem(
                  icon: Icons.analytics_outlined,
                  title: "Phân tích 7 ngày qua",
                  subtitle: "Calo, Macro & Xu hướng",
                  color: Colors.blueAccent,
                  onTap: () {
                    _handlePromptAction(
                        "Dựa trên dữ liệu log ăn uống và tập luyện 7 ngày gần nhất của tôi mà bạn có, hãy phân tích chi tiết:\n1. Xu hướng calo (thừa hay thiếu?).\n2. Tỉ lệ Macro (Protein/Carb/Fat) đã ổn chưa?\n3. Đưa ra 3 lời khuyên cụ thể để cải thiện trong tuần tới.");
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.restaurant_menu,
                  title: "Gợi ý thực đơn hôm nay",
                  subtitle: "Dựa trên TDEE của tôi",
                  color: Colors.orangeAccent,
                  onTap: () {
                    _handlePromptAction(
                        "Hãy gợi ý cho tôi thực đơn chi tiết 3 bữa cho ngày hôm nay. Tính toán sao cho phù hợp với TDEE và mục tiêu cân nặng của tôi. Trình bày dạng bảng.");
                  },
                ),
                const Divider(color: Colors.white10, height: 30),
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
            padding: const EdgeInsets.all(20),
            child: Text(
              "Version 2.1.0 (SAMAN OS)",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ... (Các hàm helper _buildSectionTitle, _buildDrawerItem, _handlePromptAction, _showPersonaDialog, _buildPersonaOption giữ nguyên)
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
      child: Text(title,
          style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2)),
    );
  }

  Widget _buildDrawerItem(
      {required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
      Color color = Colors.white}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12))
          : null,
      onTap: onTap,
      hoverColor: Colors.white10,
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
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Chọn phong cách huấn luyện",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
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
        );
      },
    );
  }

  Widget _buildPersonaOption(
      String emoji, String name, String desc, String prompt) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        ref.read(chatControllerProvider.notifier).sendMessage(prompt);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(desc,
                      style:
                          TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14),
          ],
        ),
      ),
    );
  }
}
