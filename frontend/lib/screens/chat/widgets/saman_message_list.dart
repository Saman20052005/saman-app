import 'package:flutter/material.dart';
import '../../../controllers/chat_controller.dart';
import 'saman_assistant_response.dart';
import 'saman_error_response.dart';
import 'saman_food_analysis_loading.dart';
import 'saman_food_failure.dart';
import 'saman_food_result.dart';
import 'saman_generating_indicator.dart';
import 'saman_user_message.dart';
import 'saman_user_photo_message.dart';

/// Scrollable message feed for Saman Chat active conversations,
/// supporting text messages (State 02, 05, 07) and food photo analysis (State 03, 06, 08).
class SamanMessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onEditQuestion;
  final ChatFoodAnalysisState? foodAnalysisState;
  final VoidCallback? onLogMeal;
  final VoidCallback? onRetakeFoodPhoto;
  final VoidCallback? onManualMealEntry;

  const SamanMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onEditQuestion,
    this.foodAnalysisState,
    this.onLogMeal,
    this.onRetakeFoodPhoto,
    this.onManualMealEntry,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null;
    final showGenerating =
        !hasError && isLoading && messages.isNotEmpty && messages.last.role == 'user';
    final extraCount = (hasError || showGenerating) ? 1 : 0;
    final foodCount = foodAnalysisState != null ? 2 : 0;
    final totalCount = foodCount + messages.length + extraCount;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480.0),
        child: ListView.separated(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          itemCount: totalCount,
          separatorBuilder: (_, __) => const SizedBox(height: 20.0),
          itemBuilder: (context, index) {
            // 1. Food photo user submission
            if (foodAnalysisState != null && index == 0) {
              return SamanUserPhotoMessage(
                imagePath: foodAnalysisState!.imagePath ?? '',
                caption: foodAnalysisState!.userCaption,
              );
            }

            // 2. Food photo analysis assistant response
            if (foodAnalysisState != null && index == 1) {
              final status = foodAnalysisState!.status;
              if (status == FoodAnalysisStatus.analyzing) {
                return const SamanFoodAnalysisLoading();
              }
              if (status == FoodAnalysisStatus.success &&
                  foodAnalysisState!.result != null) {
                return SamanFoodResult(
                  result: foodAnalysisState!.result!,
                  isMealLogged: foodAnalysisState!.isMealLogged,
                  onLogMeal: onLogMeal ?? () {},
                );
              }
              return SamanFoodFailure(
                onRetake: onRetakeFoodPhoto ?? () {},
                onManualEntry: onManualMealEntry ?? () {},
              );
            }

            // 3. Regular chat messages
            final msgIndex = index - foodCount;
            if (msgIndex < messages.length) {
              final msg = messages[msgIndex];
              if (msg.role == 'user') {
                return SamanUserMessage(message: msg);
              }
              return SamanAssistantResponse(message: msg);
            }

            // 4. Text error or generating indicator
            if (hasError) {
              return SamanErrorResponse(
                errorMessage: errorMessage!,
                onRetry: onRetry,
                onEditQuestion: onEditQuestion,
              );
            }
            return const SamanGeneratingIndicator();
          },
        ),
      ),
    );
  }
}
