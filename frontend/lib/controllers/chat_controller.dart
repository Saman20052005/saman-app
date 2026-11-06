import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../models/ai_analysis_result.dart';
import '../services/api_client.dart';
import '../services/analytics_service.dart';
import '../services/nutrition_service.dart';
import 'package:dio/dio.dart';
import '../presentation/providers/workout_history_providers.dart';
import '../utils/auth_helper.dart';

String generateChatOperationId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

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
  final String? mode;
  final NutritionRequestContext? owner;

  const ChatFoodAnalysisState({
    required this.status,
    this.imagePath,
    this.imageFile,
    this.userCaption,
    this.result,
    this.errorMessage,
    this.isMealLogged = false,
    this.mode,
    this.owner,
  });

  ChatFoodAnalysisState copyWith({
    FoodAnalysisStatus? status,
    String? imagePath,
    XFile? imageFile,
    String? userCaption,
    AIAnalysisResult? result,
    String? errorMessage,
    bool? isMealLogged,
    String? mode,
    NutritionRequestContext? owner,
  }) {
    return ChatFoodAnalysisState(
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      imageFile: imageFile ?? this.imageFile,
      userCaption: userCaption ?? this.userCaption,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      isMealLogged: isMealLogged ?? this.isMealLogged,
      mode: mode ?? this.mode,
      owner: owner ?? this.owner,
    );
  }
}

enum AIMode { swift3, core3, pro3 }

// --- 3. STATE ---
class ChatState {
  // Only the verified Core 3 contract is selectable during the pilot.
  AIMode get selectedAIMode => AIMode.core3;

  final List<ChatMessage> messages;
  final bool isLoading;
  final String? errorMessage;
  final String? failedUserMessage;
  final ChatFoodAnalysisState? foodAnalysisState;
  final String? activeConversationId;
  final List<ChatConversationSummary> recentConversations;
  final bool isLoadingHistory;
  final Map<String, dynamic>? pendingAction;

  ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.errorMessage,
    this.failedUserMessage,
    this.foodAnalysisState,
    this.activeConversationId,
    this.recentConversations = const [],
    this.isLoadingHistory = false,
    this.pendingAction,
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
    Map<String, dynamic>? pendingAction,
    bool clearPendingAction = false,
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
      pendingAction: clearPendingAction
          ? null
          : (pendingAction ?? this.pendingAction),
    );
  }
}

// --- 4. CONTROLLER TỐI ƯU ---
class ChatController extends StateNotifier<ChatState> {
  final Ref ref;
  final NutritionService _nutritionService;
  final AnalyticsService _analyticsService;
  int _requestEpoch = 0;
  int _foodAnalysisEpoch = 0;
  String? _currentAccountToken;
  String? _failedOperationId;
  Map<String, dynamic>? _failedPayload;
  final Map<String, String> _analyticsOperationIds = {};

  ChatController(this.ref,
      {NutritionService? nutritionService, AnalyticsService? analyticsService})
      : _nutritionService = nutritionService ?? NutritionService(),
        _analyticsService = analyticsService ?? AnalyticsService(),
        super(ChatState(messages: [])) {
    ref.listen(workoutAuthScopeProvider, (_, __) => _onAuthScopeChanged());
    ref.listen(authLoggingOutProvider, (_, next) {
      if (next) _invalidateFood();
    });
  }

  void _onAuthScopeChanged() {
    _requestEpoch++;
    _foodAnalysisEpoch++;
    _currentAccountToken = null;
    _failedOperationId = null;
    _failedPayload = null;
    _analyticsOperationIds.clear();
    if (mounted) {
      state = ChatState(messages: [], recentConversations: []);
    }
  }

  void _invalidateFood() {
    _requestEpoch++;
    _foodAnalysisEpoch++;
    if (mounted) {
      state = state.copyWith(clearFoodAnalysis: true, isLoading: false);
    }
  }

  Future<String?> _readActiveToken() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: 'auth_token') ??
        await storage.read(key: 'jwt_token');
  }

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
      clearPendingAction: true,
    );

    final opId = _newOperationId();
    _failedOperationId = opId;
    _failedPayload = null;
    await _sendRequest(trimmed, operationId: opId);
  }

  /// Retries sending the failed user message without duplicating it in messages list
  Future<void> retry() async {
    final textToRetry = state.failedUserMessage ??
        (state.messages.isNotEmpty && state.messages.last.role == 'user'
            ? state.messages.last.content
            : null);
    if (textToRetry == null) return;
    final operationId = _failedOperationId;
    if (operationId == null) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
      clearPendingAction: true,
    );

    await _sendRequest(textToRetry,
        operationId: operationId, existingPayload: _failedPayload);
  }

  /// Clears the visible recoverable error state
  void clearError() {
    state = state.copyWith(
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  Future<void> _sendRequest(String text,
      {required String operationId,
      Map<String, dynamic>? existingPayload}) async {
    final epoch = ++_requestEpoch;
    try {
      // Core 3 context is server-authoritative and allowlisted.

      // 2. LOGIC: Xây dựng Context an toàn

      // 3. API: Gửi Payload
      final payload = existingPayload ??
          <String, dynamic>{
            "message": text,
            "history": _getLastMessages(5, excludeLatestUser: true),
            "contract_version": "core3-local-v1",
            "operation_id": operationId,
          };
      if (existingPayload == null &&
          state.activeConversationId != null &&
          state.activeConversationId!.isNotEmpty) {
        payload["conversation_id"] = state.activeConversationId;
      }
      _failedPayload = Map<String, dynamic>.from(payload);

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
        final returnedAction = data['action'] is Map
            ? Map<String, dynamic>.from(data['action'] as Map)
            : null;

        final botMsg = ChatMessage(role: 'assistant', content: aiReply);

        String? nextActiveId = state.activeConversationId;
        if (returnedConvId != null && returnedConvId.isNotEmpty) {
          nextActiveId = returnedConvId;
        }

        if (!mounted || _requestEpoch != epoch) return;
        state = state.copyWith(
          messages: [...state.messages, botMsg],
          activeConversationId: nextActiveId,
          pendingAction: returnedAction,
          clearPendingAction: returnedAction == null,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );
        _failedOperationId = null;
        _failedPayload = null;

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

  String _newOperationId() {
    return generateChatOperationId();
  }

  Future<String> executeHistoryAnalytics(AnalyticsQuote quote) async {
    final scopeAtStart = ref.read(workoutAuthScopeProvider);
    final operationId = _analyticsOperationIds.putIfAbsent(
      quote.quoteId,
      _newOperationId,
    );
    final response = await _analyticsService.executeAnalytics(
      quoteId: quote.quoteId,
      rangeDays: quote.rangeDays,
      confirm: true,
      operationId: operationId,
    );
    if (!mounted ||
        ref.read(authLoggingOutProvider) ||
        ref.read(workoutAuthScopeProvider) != scopeAtStart) {
      throw StateError('Account changed during analytics request.');
    }
    final report = response['report']?.toString() ?? '';
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(role: 'assistant', content: report)
      ],
    );
    _analyticsOperationIds.remove(quote.quoteId);
    return report;
  }

  /// Checkpoint 4a: Xác nhận pending action (thêm 250 ml nước)
  Future<void> _confirmAction(String conversationId, String actionId) async {
    if (conversationId.isEmpty || actionId.isEmpty) return;
    final epoch = ++_requestEpoch;
    final scopeAtStart = ref.read(workoutAuthScopeProvider);
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );

    String? tokenAtStart;
    try {
      tokenAtStart = await _readActiveToken();
      if (_requestEpoch != epoch || !mounted) return;

      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/chat/actions/confirm",
        data: {
          "conversation_id": conversationId,
          "action_id": actionId,
        },
      );

      if (_requestEpoch != epoch || !mounted) return;
      if (ref.read(authLoggingOutProvider) ||
          ref.read(workoutAuthScopeProvider) != scopeAtStart) {
        return;
      }
      final tokenNow = await _readActiveToken();
      if (_requestEpoch != epoch || !mounted || tokenNow != tokenAtStart) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final actionType = state.pendingAction?['type'];
        final message = data['message']?.toString() ??
            (actionType == 'log_meal'
                ? "Đã ghi nhận bữa ăn vào nhật ký hôm nay của bạn."
                : (actionType == 'adjust_workout'
                    ? "Đã điều chỉnh kế hoạch tập thành công."
                    : "Đã thêm 250 ml nước vào nhật ký hôm nay của bạn."));

        final botMsg = ChatMessage(role: 'assistant', content: message);
        state = state.copyWith(
          messages: [...state.messages, botMsg],
          clearPendingAction: true,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (_requestEpoch != epoch || !mounted) return;
      if (ref.read(authLoggingOutProvider) ||
          ref.read(workoutAuthScopeProvider) != scopeAtStart) {
        return;
      }
      final tokenNow = await _readActiveToken();
      if (_requestEpoch != epoch || !mounted || tokenNow != tokenAtStart) return;
      debugPrint("Confirm Action Error: $e");
      state = state.copyWith(
        isLoading: false,
        errorMessage: "I couldn't confirm that action.",
      );
    }
  }

  /// Checkpoint 4a: Hủy pending action
  Future<void> _cancelAction(String conversationId, String actionId) async {
    if (conversationId.isEmpty || actionId.isEmpty) return;
    final epoch = ++_requestEpoch;
    final scopeAtStart = ref.read(workoutAuthScopeProvider);
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );

    String? tokenAtStart;
    try {
      tokenAtStart = await _readActiveToken();
      if (_requestEpoch != epoch || !mounted) return;

      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/chat/actions/cancel",
        data: {
          "conversation_id": conversationId,
          "action_id": actionId,
        },
      );

      if (_requestEpoch != epoch || !mounted) return;
      if (ref.read(authLoggingOutProvider) ||
          ref.read(workoutAuthScopeProvider) != scopeAtStart) {
        return;
      }
      final tokenNow = await _readActiveToken();
      if (_requestEpoch != epoch || !mounted || tokenNow != tokenAtStart) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final actionType = state.pendingAction?['type'];
        final message = data['message']?.toString() ??
            (actionType == 'log_meal'
                ? "Đã hủy thao tác ghi nhận bữa ăn."
                : (actionType == 'adjust_workout'
                    ? "Đã hủy thao tác điều chỉnh kế hoạch tập."
                    : "Đã hủy thao tác thêm nước."));

        final botMsg = ChatMessage(role: 'assistant', content: message);
        state = state.copyWith(
          messages: [...state.messages, botMsg],
          clearPendingAction: true,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (_requestEpoch != epoch || !mounted) return;
      if (ref.read(authLoggingOutProvider) ||
          ref.read(workoutAuthScopeProvider) != scopeAtStart) {
        return;
      }
      final tokenNow = await _readActiveToken();
      if (_requestEpoch != epoch || !mounted || tokenNow != tokenAtStart) return;
      debugPrint("Cancel Action Error: $e");
      state = state.copyWith(
        isLoading: false,
        errorMessage: "I couldn't cancel that action.",
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
        _failedOperationId = null;
        _failedPayload = null;
        _analyticsOperationIds.clear();
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
    _failedOperationId = null;
    _failedPayload = null;
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

        final rawPendingAction = data['pending_action'] is Map
            ? Map<String, dynamic>.from(data['pending_action'] as Map)
            : null;

        if (!mounted || _requestEpoch != epoch) return;
        state = state.copyWith(
          messages: loadedMessages,
          activeConversationId: conversationId,
          pendingAction: rawPendingAction,
          clearPendingAction: rawPendingAction == null,
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
    _foodAnalysisEpoch++;
    _failedOperationId = null;
    _failedPayload = null;
    state = state.copyWith(
      messages: [],
      clearActiveConversation: true,
      clearPendingAction: true,
      clearError: true,
      clearFailedUserMessage: true,
      clearFoodAnalysis: true,
      isLoading: false,
      isLoadingHistory: false,
    );
  }

  Future<void> analyzeFoodPhoto(XFile file, {String? caption, String? mode}) async {
    final epoch = ++_foodAnalysisEpoch;
    final guard = ref.read(nutritionSessionProvider);
    NutritionRequestContext? owner;
    state = state.copyWith(
      foodAnalysisState: ChatFoodAnalysisState(
        status: FoodAnalysisStatus.analyzing,
        imagePath: file.path,
        imageFile: file,
        userCaption: caption ?? 'Can I fit this into today?',
        mode: mode,
      ),
      clearError: true,
      clearFailedUserMessage: true,
    );
    try {
      owner = await guard.capture();
      if (!mounted || epoch != _foodAnalysisEpoch) return;
      await owner.validate();
      final result = await _nutritionService.analyzeFoodImage(file,
          mode: mode, session: owner);
      await owner.validate();
      if (!mounted || epoch != _foodAnalysisEpoch) return;
      final failed = result == null || (result.calories <= 0 && result.lowConfidence);
      state = state.copyWith(foodAnalysisState: ChatFoodAnalysisState(
        status: failed ? FoodAnalysisStatus.failure : FoodAnalysisStatus.success,
        imagePath: file.path,
        imageFile: file,
        userCaption: caption ?? 'Can I fit this into today?',
        mode: mode,
        owner: owner,
        result: failed ? null : result,
        errorMessage: failed ? "I couldn't estimate this meal confidently from the photo." : null,
      ));
    } catch (error) {
      if (!mounted || epoch != _foodAnalysisEpoch) return;
      try {
        await owner?.validate();
      } on NutritionSessionChanged {
        _invalidateFood();
        return;
      }
      if (!mounted || epoch != _foodAnalysisEpoch) return;
      if (error is NutritionSessionChanged ||
          (error is DioException && error.error is NutritionSessionChanged)) {
        _invalidateFood();
        return;
      }
      state = state.copyWith(foodAnalysisState: ChatFoodAnalysisState(
        status: FoodAnalysisStatus.failure,
        imagePath: file.path,
        imageFile: file,
        userCaption: caption ?? 'Can I fit this into today?',
        mode: mode,
        errorMessage: foodAnalysisErrorMessage(error),
      ));
      if (error is DioException && error.response?.statusCode == 401) {
        await guard.recoverAuthorization();
      }
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
    _foodAnalysisEpoch++;
    state = state.copyWith(clearFoodAnalysis: true);
  }

  void clearChat() {
    newConversation();
  }

  List<Map<String, String>> _getLastMessages(int count,
      {bool excludeLatestUser = false}) {
    final msgs = List<ChatMessage>.from(state.messages);
    if (excludeLatestUser && msgs.isNotEmpty && msgs.last.role == 'user') {
      msgs.removeLast();
    }
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

// --- 5. ACTION EXTENSION & DELEGATE (Checkpoint 4a) ---
/// Optional delegate interface allowing test doubles to intercept actions
/// without modifying the class interface of ChatController.
abstract class ChatActionDelegate {
  Future<void> handleConfirmAction(String conversationId, String actionId);
  Future<void> handleCancelAction(String conversationId, String actionId);
}

// Giữ confirmAction và cancelAction dưới dạng extension để không làm thay đổi
// implicit class interface của ChatController, bảo vệ các test/mock hiện có.
extension ChatControllerActionExtension on ChatController {
  Future<void> confirmAction(String conversationId, String actionId) {
    if (this is ChatActionDelegate) {
      return (this as ChatActionDelegate)
          .handleConfirmAction(conversationId, actionId);
    }
    return _confirmAction(conversationId, actionId);
  }

  Future<void> cancelAction(String conversationId, String actionId) {
    if (this is ChatActionDelegate) {
      return (this as ChatActionDelegate)
          .handleCancelAction(conversationId, actionId);
    }
    return _cancelAction(conversationId, actionId);
  }
}
