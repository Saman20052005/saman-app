import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/ai_analysis_result.dart';
import '../services/api_client.dart';
import '../services/nutrition_service.dart';

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

// --- 1b. MODEL CONVERSATION SUMMARY ---
class ChatConversationSummary {
  final String id;
  final String title;
  final String updatedAt;
  final String createdAt;

  ChatConversationSummary({
    required this.id,
    required this.title,
    this.updatedAt = '',
    this.createdAt = '',
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    return ChatConversationSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Cuộc trò chuyện',
      updatedAt: json['updated_at']?.toString() ?? json['created_at']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

// --- 2. FOOD PHOTO ANALYSIS STATE ---
enum FoodAnalysisStatus {
  idle,
  analyzing,
  success,
  failure,
}

class ChatFoodAnalysisState {
  final FoodAnalysisStatus status;
  final String? imagePath;
  final XFile? imageFile;
  final String? userCaption;
  final AIAnalysisResult? result;
  final String? errorMessage;
  final bool isMealLogged;

  const ChatFoodAnalysisState({
    required this.status,
    this.imagePath,
    this.imageFile,
    this.userCaption,
    this.result,
    this.errorMessage,
    this.isMealLogged = false,
  });

  ChatFoodAnalysisState copyWith({
    FoodAnalysisStatus? status,
    String? imagePath,
    XFile? imageFile,
    String? userCaption,
    AIAnalysisResult? result,
    String? errorMessage,
    bool? isMealLogged,
  }) {
    return ChatFoodAnalysisState(
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      imageFile: imageFile ?? this.imageFile,
      userCaption: userCaption ?? this.userCaption,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      isMealLogged: isMealLogged ?? this.isMealLogged,
    );
  }
}

// --- 3. STATE ---
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? errorMessage;
  final String? failedUserMessage;
  final ChatFoodAnalysisState? foodAnalysisState;
  final String? activeConversationId;
  final List<ChatConversationSummary> recentConversations;
  final bool isLoadingHistory;

  ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.errorMessage,
    this.failedUserMessage,
    this.foodAnalysisState,
    this.activeConversationId,
    this.recentConversations = const [],
    this.isLoadingHistory = false,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    String? failedUserMessage,
    bool clearFailedUserMessage = false,
    ChatFoodAnalysisState? foodAnalysisState,
    bool clearFoodAnalysis = false,
    String? activeConversationId,
    bool clearActiveConversation = false,
    List<ChatConversationSummary>? recentConversations,
    bool? isLoadingHistory,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      failedUserMessage: clearFailedUserMessage
          ? null
          : (failedUserMessage ?? this.failedUserMessage),
      foodAnalysisState: clearFoodAnalysis
          ? null
          : (foodAnalysisState ?? this.foodAnalysisState),
      activeConversationId: clearActiveConversation
          ? null
          : (activeConversationId ?? this.activeConversationId),
      recentConversations: recentConversations ?? this.recentConversations,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
    );
  }
}

// --- 4. CONTROLLER TỐI ƯU ---
class ChatController extends StateNotifier<ChatState> {
  final Ref ref;
  final NutritionService _nutritionService;
  int _requestEpoch = 0;
  String? _currentAccountToken;

  ChatController(this.ref, {NutritionService? nutritionService})
      : _nutritionService = nutritionService ?? NutritionService(),
        super(ChatState(messages: []));

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // 1. UI: Hiện tin nhắn User ngay lập tức
    final userMsg = ChatMessage(role: 'user', content: trimmed);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );

    await _sendRequest(trimmed);
  }

  /// Retries sending the failed user message without duplicating it in messages list
  Future<void> retry() async {
    final textToRetry = state.failedUserMessage ??
        (state.messages.isNotEmpty && state.messages.last.role == 'user'
            ? state.messages.last.content
            : null);
    if (textToRetry == null) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );

    await _sendRequest(textToRetry);
  }

  /// Clears the visible recoverable error state
  void clearError() {
    state = state.copyWith(
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  Future<void> _sendRequest(String text) async {
    final epoch = ++_requestEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();

      // 2. LOGIC: Xây dựng Context an toàn
      final userContext = await _buildUserContext(prefs);

      // 3. API: Gửi Payload
      final payload = <String, dynamic>{
        "message": text,
        "context": userContext,
        "history": _getLastMessages(5),
      };
      if (state.activeConversationId != null &&
          state.activeConversationId!.isNotEmpty) {
        payload["conversation_id"] = state.activeConversationId;
      }

      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/chat",
        data: payload,
      );

      // Ngăn response tải muộn khôi phục chat cũ sau New conversation hoặc đổi tài khoản
      if (_requestEpoch != epoch || !mounted) return;

      // 4. Xử lý phản hồi
      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final aiReply = data['reply'];
        final returnedConvId = data['conversation_id']?.toString();

        final botMsg = ChatMessage(role: 'assistant', content: aiReply);

        String? nextActiveId = state.activeConversationId;
        if (returnedConvId != null && returnedConvId.isNotEmpty) {
          nextActiveId = returnedConvId;
        }

        if (!mounted || _requestEpoch != epoch) return;
        state = state.copyWith(
          messages: [...state.messages, botMsg],
          activeConversationId: nextActiveId,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );

        // Cập nhật danh sách conversations gần đây để hiển thị title mới
        if (mounted) {
          loadConversations(loadLatest: false);
        }
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (_requestEpoch != epoch || !mounted) return;
      debugPrint("Chat Error: $e");
      state = state.copyWith(
        isLoading: false,
        errorMessage: "I couldn't complete that response.",
        failedUserMessage: text,
      );
    }
  }

  /// Tải danh sách conversations gần đây của user
  Future<void> loadConversations({bool loadLatest = false}) async {
    final epoch = ++_requestEpoch;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ??
          await storage.read(key: 'jwt_token');

      // Chống rò rỉ state khi đổi tài khoản: nếu token đổi, xóa sạch state cũ
      if (_currentAccountToken != token) {
        if (_currentAccountToken != null || state.messages.isNotEmpty) {
          if (!mounted) return;
          state = ChatState(messages: [], recentConversations: []);
        }
      }
      _currentAccountToken = token;

      final response = await ApiClient.dio.get(
        "${ApiConfig.baseUrl}/api/chat/conversations",
      );

      if (_requestEpoch != epoch || !mounted) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        List rawList = [];
        if (data is List) {
          rawList = data;
        } else if (data is Map && data['conversations'] is List) {
          rawList = data['conversations'] as List;
        }

        final summaries = rawList
            .map((item) => ChatConversationSummary.fromJson(
                item is Map<String, dynamic>
                    ? item
                    : Map<String, dynamic>.from(item as Map)))
            .toList();

        if (!mounted || _requestEpoch != epoch) return;
        state = state.copyWith(recentConversations: summaries);

        // Mở Chat: tải conversation gần nhất nếu chưa có active ID
        if (loadLatest && state.activeConversationId == null && summaries.isNotEmpty) {
          await loadConversation(summaries.first.id);
        }
      }
    } catch (e) {
      debugPrint("Failed to load conversations: $e");
    }
  }

  /// Tải lịch sử tin nhắn của một conversation cụ thể
  Future<void> loadConversation(String conversationId) async {
    final epoch = ++_requestEpoch;
    if (!mounted) return;
    state = state.copyWith(
      activeConversationId: conversationId,
      isLoadingHistory: true,
      clearError: true,
      clearFailedUserMessage: true,
    );

    try {
      final response = await ApiClient.dio.get(
        "${ApiConfig.baseUrl}/api/chat/conversations/$conversationId",
      );

      if (_requestEpoch != epoch || !mounted) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        final rawMessages = data['messages'] as List? ?? [];
        final loadedMessages = rawMessages.map<ChatMessage>((m) {
          final role = m['role']?.toString() ?? 'user';
          final content = m['content']?.toString() ?? '';
          return ChatMessage(role: role, content: content);
        }).toList();

        if (!mounted || _requestEpoch != epoch) return;
        state = state.copyWith(
          messages: loadedMessages,
          activeConversationId: conversationId,
          isLoadingHistory: false,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );
      } else {
        throw Exception("Status ${response.statusCode}");
      }
    } catch (e) {
      if (_requestEpoch != epoch || !mounted) return;
      debugPrint("Failed to load conversation details: $e");
      state = state.copyWith(
        isLoadingHistory: false,
        isLoading: false,
        errorMessage: "I couldn't load that conversation.",
      );
    }
  }

  /// Bắt đầu cuộc trò chuyện mới, xóa ID đang chọn và hủy các response cũ
  void newConversation() {
    _requestEpoch++;
    state = state.copyWith(
      messages: [],
      clearActiveConversation: true,
      clearError: true,
      clearFailedUserMessage: true,
      clearFoodAnalysis: true,
      isLoading: false,
      isLoadingHistory: false,
    );
  }

  Future<void> analyzeFoodPhoto(XFile file, {String? caption}) async {
    state = state.copyWith(
      foodAnalysisState: ChatFoodAnalysisState(
        status: FoodAnalysisStatus.analyzing,
        imagePath: file.path,
        imageFile: file,
        userCaption: caption ?? 'Can I fit this into today?',
      ),
      clearError: true,
      clearFailedUserMessage: true,
    );

    try {
      final analysisResult = await _nutritionService.analyzeFoodImage(file);

      if (analysisResult == null ||
          (analysisResult.calories <= 0 && analysisResult.lowConfidence)) {
        state = state.copyWith(
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.failure,
            imagePath: file.path,
            imageFile: file,
            userCaption: caption ?? 'Can I fit this into today?',
            errorMessage:
                "I couldn't estimate this meal confidently from the photo.",
          ),
        );
      } else {
        state = state.copyWith(
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.success,
            imagePath: file.path,
            imageFile: file,
            userCaption: caption ?? 'Can I fit this into today?',
            result: analysisResult,
          ),
        );
      }
    } catch (e) {
      debugPrint("Food photo analysis error: $e");
      state = state.copyWith(
        foodAnalysisState: ChatFoodAnalysisState(
          status: FoodAnalysisStatus.failure,
          imagePath: file.path,
          imageFile: file,
          userCaption: caption ?? 'Can I fit this into today?',
          errorMessage:
              "I couldn't estimate this meal confidently from the photo.",
        ),
      );
    }
  }

  void markMealLogged() {
    if (state.foodAnalysisState != null) {
      state = state.copyWith(
        foodAnalysisState: state.foodAnalysisState!.copyWith(
          isMealLogged: true,
        ),
      );
    }
  }

  void clearFoodAnalysis() {
    state = state.copyWith(clearFoodAnalysis: true);
  }

  void clearChat() {
    newConversation();
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
