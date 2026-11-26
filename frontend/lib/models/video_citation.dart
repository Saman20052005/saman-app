import 'package:flutter/foundation.dart';

@immutable
class VideoCitation {
  final String videoStoryId;
  final String videoUrl;
  final String label;
  final double seekSec;
  final String? exerciseSlug;
  final int? repIndex;
  final String? issueType;

  const VideoCitation({
    required this.videoStoryId,
    required this.videoUrl,
    required this.label,
    this.seekSec = 0.0,
    this.exerciseSlug,
    this.repIndex,
    this.issueType,
  });

  factory VideoCitation.fromJson(Map<String, dynamic> json) {
    final rawStoryId = json['video_story_id'] ?? json['videoStoryId'];
    final rawUrl = json['video_url'] ?? json['videoUrl'];
    final rawLabel = json['label'];
    final rawSeek = json['seek_sec'] ?? json['seekSec'];
    final rawSlug = json['exercise_slug'] ?? json['exerciseSlug'];
    final rawRep = json['rep_index'] ?? json['repIndex'];
    final rawIssue = json['issue_type'] ?? json['issueType'];

    return VideoCitation(
      videoStoryId: rawStoryId?.toString().trim() ?? '',
      videoUrl: rawUrl?.toString().trim() ?? '',
      label: rawLabel?.toString() ?? '',
      seekSec: _parseSeekSec(rawSeek),
      exerciseSlug: _parseOptionalString(rawSlug),
      repIndex: _parseOptionalInt(rawRep),
      issueType: _parseOptionalString(rawIssue),
    );
  }

  static List<VideoCitation> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final results = <VideoCitation>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item);
      final citation = VideoCitation.fromJson(map);
      if (citation.videoUrl.isNotEmpty) {
        results.add(citation);
      }
    }
    return results;
  }

  String get formattedTimestamp {
    final totalSeconds =
        seekSec.isFinite && seekSec > 0 ? seekSec.floor() : 0;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'video_story_id': videoStoryId,
      'video_url': videoUrl,
      'label': label,
      'seek_sec': seekSec,
      if (exerciseSlug != null) 'exercise_slug': exerciseSlug,
      if (repIndex != null) 'rep_index': repIndex,
      if (issueType != null) 'issue_type': issueType,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoCitation &&
        other.videoStoryId == videoStoryId &&
        other.videoUrl == videoUrl &&
        other.label == label &&
        other.seekSec == seekSec &&
        other.exerciseSlug == exerciseSlug &&
        other.repIndex == repIndex &&
        other.issueType == issueType;
  }

  @override
  int get hashCode => Object.hash(
        videoStoryId,
        videoUrl,
        label,
        seekSec,
        exerciseSlug,
        repIndex,
        issueType,
      );

  static double _parseSeekSec(dynamic raw) {
    double value = 0.0;
    if (raw is num) {
      value = raw.toDouble();
    } else if (raw is String) {
      value = double.tryParse(raw.trim()) ?? 0.0;
    }
    if (!value.isFinite || value < 0.0) {
      return 0.0;
    }
    return value;
  }

  static int? _parseOptionalInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static String? _parseOptionalString(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }
}
