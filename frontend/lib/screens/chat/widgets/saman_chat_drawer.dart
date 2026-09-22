import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';

/// Approved Full-Height Drawer component for Saman Chat (State 10).
///
/// Features:
/// - Full-height left overlay, ~80% width with visible dark scrim to the right
/// - Top micro-context: "Saman · Your personal coach"
/// - "+ New conversation" primary action
/// - "Recent" conversation section with presentation references
/// - "Coach tools" section mapped to actual prompt workflows
/// - Bottom utility rows: "Reminders" (neutral) and "Saman preferences"
/// - No legacy DrawerHeader, no "Adaptive AI", no uppercase titles, no version footer
class SamanChatDrawer extends StatelessWidget {
  final VoidCallback onNewChat;
  final ValueChanged<String> onPromptSelected;
  final VoidCallback onOpenPreferences;
  final bool hasActiveReminders;

  const SamanChatDrawer({
    super.key,
    required this.onNewChat,
    required this.onPromptSelected,
    required this.onOpenPreferences,
    this.hasActiveReminders = false,
  });

  static const String weeklyReviewPrompt =
      "Dựa trên dữ liệu log ăn uống và tập luyện 7 ngày gần nhất của tôi mà bạn có, hãy phân tích chi tiết:\n1. Xu hướng calo (thừa hay thiếu?).\n2. Tỉ lệ Macro (Protein/Carb/Fat) đã ổn chưa?\n3. Đưa ra 3 lời khuyên cụ thể để cải thiện trong tuần tới.";

  static const String nutritionReviewPrompt =
      "Hãy gợi ý cho tôi thực đơn chi tiết 3 bữa cho ngày hôm nay. Tính toán sao cho phù hợp với TDEE và mục tiêu cân nặng của tôi. Trình bày dạng bảng.";

  static const String workoutAnalysisPrompt =
      "Hãy phân tích buổi tập gần nhất của tôi: khối lượng, cường độ RPE và đề xuất điều chỉnh cho buổi tập tiếp theo.";

  void _handleRecentPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Previous conversation history will be available in a future update.',
          style: TextStyle(color: SamanChatTokens.textWhite, fontSize: 13),
        ),
        backgroundColor: SamanChatTokens.surfaceElevated,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleRemindersPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Reminders and proactive notifications will arrive in the next phase.',
          style: TextStyle(color: SamanChatTokens.textWhite, fontSize: 13),
        ),
        backgroundColor: SamanChatTokens.surfaceElevated,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = (screenWidth * 0.82).clamp(280.0, 340.0);

    return Drawer(
      width: drawerWidth,
      backgroundColor: SamanChatTokens.drawerBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: SamanChatTokens.drawerBg,
          border: Border(
            right: BorderSide(
              color: SamanChatTokens.borderSubtle,
              width: 1.0,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top micro-context
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                  child: Text(
                    'Saman · Your personal coach',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: SamanChatTokens.textMuted,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),

                const SizedBox(height: 10.0),

                // 2. New conversation button
                InkWell(
                  borderRadius: BorderRadius.circular(12.0),
                  onTap: () {
                    Navigator.pop(context);
                    onNewChat();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 11.0),
                    decoration: BoxDecoration(
                      color: SamanChatTokens.surface,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: SamanChatTokens.borderSubtle,
                        width: 1.0,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: SamanChatTokens.textSecondary,
                        ),
                        SizedBox(width: 8.0),
                        Flexible(
                          child: Text(
                            'New conversation',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: SamanChatTokens.textWhite,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Scrollable middle area (Recent & Coach tools)
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    children: [
                      // --- Recent Section ---
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                        child: Text(
                          'Recent',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: SamanChatTokens.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6.0),
                      _RecentConversationRow(
                        title: 'Upper body form check',
                        timestamp: 'Yesterday',
                        isSelected: true,
                        onTap: () => Navigator.pop(context),
                      ),
                      _RecentConversationRow(
                        title: 'Post-workout meal plan',
                        timestamp: 'Mon',
                        isSelected: false,
                        onTap: () => _handleRecentPlaceholder(context),
                      ),
                      _RecentConversationRow(
                        title: 'Lower-back adjustment',
                        timestamp: 'Sun',
                        isSelected: false,
                        onTap: () => _handleRecentPlaceholder(context),
                      ),
                      _RecentConversationRow(
                        title: 'Macro review',
                        timestamp: 'Last week',
                        isSelected: false,
                        onTap: () => _handleRecentPlaceholder(context),
                      ),
                      const SizedBox(height: 4.0),
                      InkWell(
                        borderRadius: BorderRadius.circular(8.0),
                        onTap: () => _handleRecentPlaceholder(context),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'View all conversations',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: SamanChatTokens.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 4.0),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: SamanChatTokens.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18.0),

                      // --- Coach tools Section ---
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                        child: Text(
                          'Coach tools',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: SamanChatTokens.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6.0),
                      _CoachToolRow(
                        icon: Icons.calendar_today_rounded,
                        title: 'Weekly review',
                        onTap: () {
                          Navigator.pop(context);
                          onPromptSelected(weeklyReviewPrompt);
                        },
                      ),
                      _CoachToolRow(
                        icon: Icons.restaurant_rounded,
                        title: 'Nutrition review',
                        onTap: () {
                          Navigator.pop(context);
                          onPromptSelected(nutritionReviewPrompt);
                        },
                      ),
                      _CoachToolRow(
                        icon: Icons.fitness_center_rounded,
                        title: 'Workout analysis',
                        onTap: () {
                          Navigator.pop(context);
                          onPromptSelected(workoutAnalysisPrompt);
                        },
                      ),
                    ],
                  ),
                ),

                // 4. Bottom utility area
                const Divider(
                  color: SamanChatTokens.borderSubtle,
                  height: 1.0,
                ),
                const SizedBox(height: 8.0),

                // Reminders
                _DrawerUtilityRow(
                  icon: Icons.access_time_rounded,
                  title: 'Reminders',
                  hasActiveDot: hasActiveReminders,
                  onTap: () => _handleRemindersPlaceholder(context),
                ),

                const SizedBox(height: 4.0),

                // Saman preferences
                _DrawerUtilityRow(
                  icon: Icons.tune_rounded,
                  title: 'Saman preferences',
                  subtitle: 'Coaching tone, response style, reminders',
                  onTap: () {
                    Navigator.pop(context);
                    onOpenPreferences();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentConversationRow extends StatelessWidget {
  final String title;
  final String timestamp;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecentConversationRow({
    required this.title,
    required this.timestamp,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      decoration: BoxDecoration(
        color: isSelected ? SamanChatTokens.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 9.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                    color: isSelected
                        ? SamanChatTokens.textWhite
                        : SamanChatTokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8.0),
              Text(
                timestamp,
                style: const TextStyle(
                  fontSize: 11,
                  color: SamanChatTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachToolRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _CoachToolRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 9.0),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: SamanChatTokens.textSecondary,
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: SamanChatTokens.textWhite,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SamanChatTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerUtilityRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool hasActiveDot;

  const _DrawerUtilityRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.hasActiveDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: SamanChatTokens.textSecondary,
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: SamanChatTokens.textWhite,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2.0),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: SamanChatTokens.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (hasActiveDot)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8.0),
                  decoration: const BoxDecoration(
                    color: SamanChatTokens.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SamanChatTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
