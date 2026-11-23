import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/post_attachment_snapshot.dart';

class CommunityActivitySnapshotCard extends StatelessWidget {
  final PostAttachmentSnapshot snapshot;
  const CommunityActivitySnapshotCard({super.key, required this.snapshot});
  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return ColoredBox(color: tokens.cardSurface,
      child: Padding(padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(snapshot.title, style: tokens.cardTitle),
          Text('${snapshot.category} • ${snapshot.dateFormatted}',style: tokens.headerSubtitle),
          for(final field in snapshot.displayFields)
            Text('${context.tr('community_attachment_${field.key}')}: ${field.value}',style: tokens.headerSubtitle),
        ])));
  }
}
