import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';

// --- 1. MODEL TIN NHẮN ---
class ChatMessage {
  final String role;
  final String content;
  final bool isTyping;

  ChatMessage({
    required this.role,
    required this.content,
    this.isTyping = false,
  });
}

// --- 2. STATE ---
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;

  ChatState({this.messages = const [], this.isLoading = false});

  ChatState copyWith({List<ChatMessage>? messages, bool? isLoading}) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// --- 3. CONTROLLER TỐI ƯU ---
class ChatController extends StateNotifier<ChatState> {
  final Ref ref;

  ChatController(this.ref) : super(ChatState(messages: []));

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // 1. UI: Hiện tin nhắn User ngay lập tức
    final userMsg = ChatMessage(role: 'user', content: text);
    state =
        state.copyWith(messages: [...state.messages, userMsg], isLoading: true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // 2. LOGIC: Xây dựng Context an toàn
      final userContext = await _buildUserContext(prefs);

      // 3. API: Gửi Payload
      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/chat",
        data: {
          "message": text,
          "context": userContext,
          "history": _getLastMessages(5)
        },
      );

      // 4. Xử lý phản hồi
      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final aiReply = data['reply'];

        final botMsg = ChatMessage(role: 'assistant', content: aiReply);

        state = state
            .copyWith(messages: [...state.messages, botMsg], isLoading: false);
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      state = state.copyWith(messages: [
        ...state.messages,
        ChatMessage(role: 'assistant', content: "⚠️ Có lỗi xảy ra: $e")
      ], isLoading: false);
      print("Chat Error: $e");
    }
  }

  void clearChat() {
    state = ChatState(messages: []);
  }

  // --- HELPER: XÂY DỰNG NGỮ CẢNH (ĐÃ FIX LỖI PARSE TYPE) ---
  Future<Map<String, dynamic>> _buildUserContext(
      SharedPreferences prefs) async {
    // 🔥 FIX: Dùng hàm helper _safeParseInt/Double để tránh lỗi "String is not subtype of Int"

    // 1. Thông tin cơ bản
    String name = prefs.getString('user_name') ?? "Bạn";

    // Lỗi xảy ra ở đây do 'prefs.getInt' chết khi gặp String "170"
    // Ta sửa bằng cách lấy 'get' (dynamic) rồi parse thủ công
    int height = _safeParseInt(prefs.get('user_height'), 170);
    double weight = _safeParseDouble(prefs.get('user_weight'), 65.0);
    int age = _safeParseInt(prefs.get('user_age'), 25);
    String gender = prefs.getString('user_gender') ?? "Nam";

    // 2. Chỉ số quan trọng (TDEE/BMI)
    double tdee = _safeParseDouble(prefs.get('user_tdee'), 2200.0);
    String goal = prefs.getString('user_goal') ?? "Duy trì cân nặng";

    // 3. Tracking hôm nay
    double caloriesConsumed =
        _safeParseDouble(prefs.get('daily_calories_in'), 0.0);

    return {
      "profile": {
        "name": name,
        "biometrics": "$height cm, $weight kg, $age tuổi, $gender",
        "tdee": tdee,
        "goal": goal,
      },
      "daily_stats": {
        "eaten": caloriesConsumed,
        "remaining": tdee - caloriesConsumed,
      },
      "system_instruction": """
        YOU ARE:
You are **Saman AI Coach**, a personal trainer and nutrition expert dedicated exclusively to helping **$name** achieve their fitness goal efficiently and safely.

FIXED USER DATA (DO NOT OVERRIDE OR ASSUME):
- Height: $height cm
- Weight: $weight kg
- Age: $age
- Gender: $gender
- Daily TDEE: $tdee kcal
- Goal: $goal
- Calories consumed today: $caloriesConsumed kcal
- Remaining calories today: ${tdee - caloriesConsumed} kcal

CORE RULES (MANDATORY):
1. All advice MUST be strictly based on TDEE, remaining calories, and the stated goal.
2. Do NOT give generic, motivational, or vague advice.
3. Do NOT contradict or reinterpret provided data.
4. If information is missing, make a reasonable estimation and clearly state it as an estimate.

QUERY HANDLING LOGIC:
- Food-related questions:
  - Estimate calories and macronutrients (protein, carbs, fats).
  - State clearly whether the food fits the current goal and remaining calories.
- Training-related questions:
  - Recommend exercises aligned with the goal and current calorie status.
- If a choice would exceed TDEE:
  - Give a short warning.
  - Propose a better alternative.
- If remaining calories are high:
  - Suggest optimal food or meal options to use them effectively.

RESPONSE STYLE:
- Concise and direct.
- Professional and precise.
- No emojis, no storytelling, no unnecessary explanations.

OUTPUT PRIORITY ORDER:
1. Numbers and calculations
2. Clear judgment (good / acceptable / not recommended)
3. Actionable next step

      """
    };
  }

  // 🔥 Helper: Parse Int an toàn (Chấp nhận cả String lẫn Int)
  int _safeParseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    if (value is double) return value.toInt();
    return defaultValue;
  }

  // 🔥 Helper: Parse Double an toàn
  double _safeParseDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  List<Map<String, String>> _getLastMessages(int count) {
    final msgs = state.messages;
    final startIndex = msgs.length > count ? msgs.length - count : 0;
    return msgs
        .sublist(startIndex)
        .map((m) => {"role": m.role, "content": m.content})
        .toList();
  }
}

// --- 4. PROVIDER ---
final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) {
  return ChatController(ref);
});
