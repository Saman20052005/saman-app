import 'community_author.dart';

class QuestionAnswer {
  final String id;
  final String questionId;
  final CommunityAuthor author;
  final String content;
  final String timeAgo;
  final int upvoteCount;
  final bool isUpvoted;
  final bool isPinnedBest;

  const QuestionAnswer({
    required this.id,
    required this.questionId,
    required this.author,
    required this.content,
    required this.timeAgo,
    this.upvoteCount = 0,
    this.isUpvoted = false,
    this.isPinnedBest = false,
  });

  QuestionAnswer copyWith({
    String? id,
    String? questionId,
    CommunityAuthor? author,
    String? content,
    String? timeAgo,
    int? upvoteCount,
    bool? isUpvoted,
    bool? isPinnedBest,
  }) {
    return QuestionAnswer(
      id: id ?? this.id,
      questionId: questionId ?? this.questionId,
      author: author ?? this.author,
      content: content ?? this.content,
      timeAgo: timeAgo ?? this.timeAgo,
      upvoteCount: upvoteCount ?? this.upvoteCount,
      isUpvoted: isUpvoted ?? this.isUpvoted,
      isPinnedBest: isPinnedBest ?? this.isPinnedBest,
    );
  }
}

class QuestionAnswersPage {
  final List<QuestionAnswer> items;
  final int answerCount;
  final String? nextCursor;
  const QuestionAnswersPage({required this.items, required this.answerCount, this.nextCursor});
}

class QuestionAnswerReceipt {
  final QuestionAnswer answer;
  final int answerCount;
  const QuestionAnswerReceipt({required this.answer, required this.answerCount});
}
