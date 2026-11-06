import 'community_author.dart';

/// Domain model representing a threaded comment on a community post.
class CommunityComment {
  final String id;
  final String postId;
  final CommunityAuthor author;
  final String content;
  final String timeAgo;
  final String? parentCommentId;
  final DateTime? createdAt;
  final int likeCount;
  final bool isLiked;
  final bool isAuthorReply;
  final String? replyToAuthorName;
  final List<CommunityComment> replies;

  const CommunityComment({
    required this.id,
    required this.postId,
    required this.author,
    required this.content,
    required this.timeAgo,
    this.parentCommentId,
    this.createdAt,
    this.likeCount = 0,
    this.isLiked = false,
    this.isAuthorReply = false,
    this.replyToAuthorName,
    this.replies = const [],
  });

  CommunityComment copyWith({
    String? id,
    String? postId,
    CommunityAuthor? author,
    String? content,
    String? timeAgo,
    int? likeCount,
    bool? isLiked,
    bool? isAuthorReply,
    String? replyToAuthorName,
    List<CommunityComment>? replies,
  }) {
    return CommunityComment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      author: author ?? this.author,
      content: content ?? this.content,
      timeAgo: timeAgo ?? this.timeAgo,
      parentCommentId: parentCommentId,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      isAuthorReply: isAuthorReply ?? this.isAuthorReply,
      replyToAuthorName: replyToAuthorName ?? this.replyToAuthorName,
      replies: replies ?? this.replies,
    );
  }
}


class CommunityCommentsPage {
  final List<CommunityComment> items;
  final String? nextCursor;
  final int commentCount;
  const CommunityCommentsPage({required this.items, this.nextCursor, required this.commentCount});
}

class CommunityCommentReceipt {
  final CommunityComment comment;
  final int commentCount;
  const CommunityCommentReceipt({required this.comment, required this.commentCount});
}
