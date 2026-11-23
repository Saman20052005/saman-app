import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../../domain/models/post_attachment_snapshot.dart';
import '../tokens/saman_ig_tokens.dart';

class CommunityActivitySnapshotCard extends StatelessWidget {
  final PostAttachmentSnapshot snapshot;
  const CommunityActivitySnapshotCard({super.key, required this.snapshot});
  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              snapshot.title,
              style: ig.username(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              '${snapshot.category} • ${snapshot.dateFormatted}',
              style: ig.caption(fontSize: 13, color: ig.textSecondary),
            ),
            for (final field in snapshot.displayFields)
              Text(
                '${context.tr('community_attachment_${field.key}')}: ${field.value}',
                style: ig.caption(fontSize: 13, color: ig.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
