import 'package:flutter/material.dart';
import '../../domain/models/membership_plan.dart';
import '../tokens/membership_tokens.dart';

class ComparisonMatrixTable extends StatelessWidget {
  const ComparisonMatrixTable({super.key});

  @override
  Widget build(BuildContext context) {
    final featuresByGroup = <FeatureGroup, List<MatrixFeature>>{};
    for (final feature in MembershipCatalog.matrixFeatures) {
      featuresByGroup.putIfAbsent(feature.group, () => []).add(feature);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Matrix Header with Callout
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'FEATURE MATRIX',
                style: MembershipTokens.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: MembershipTokens.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: MembershipTokens.accentBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: MembershipTokens.accentBorder,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: MembershipTokens.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Recommended: Pro',
                      style: MembershipTokens.mono(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: MembershipTokens.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Main Matrix Card
        Container(
          decoration: BoxDecoration(
            color: MembershipTokens.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sticky-style Column Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 10.0,
                ),
                decoration: const BoxDecoration(
                  color: MembershipTokens.card,
                  border: Border(
                    bottom: BorderSide(
                      color: MembershipTokens.border,
                      width: 1.0,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        'Feature',
                        style: MembershipTokens.mono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: MembershipTokens.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          _buildTierHeader('Free', isRecommended: false),
                          _buildTierHeader('Plus', isRecommended: false),
                          _buildTierHeader('Pro', isRecommended: true),
                          _buildTierHeader('Ultra', isRecommended: false),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Grouped Features
              for (final group in FeatureGroup.values) ...[
                // Group Divider Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  decoration: BoxDecoration(
                    color: MembershipTokens.surfaceHigh.withOpacity(0.5),
                    border: const Border(
                      top: BorderSide(
                        color: MembershipTokens.border,
                        width: 1.0,
                      ),
                      bottom: BorderSide(
                        color: MembershipTokens.border,
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: Text(
                    group.title,
                    style: MembershipTokens.mono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: MembershipTokens.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                // Feature rows in group
                if (featuresByGroup[group] != null)
                  for (final feature in featuresByGroup[group]!)
                    _buildFeatureRow(feature),
              ],
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Telemetry / Roadmap Notes Card
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: MembershipTokens.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: MembershipTokens.border,
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• AI and Workout CV limits will be announced.',
                style: MembershipTokens.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "• Ultra's planned AI allowance is 5× Pro.",
                style: MembershipTokens.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Note: Workout CV uses a separate allowance model.',
                style: MembershipTokens.body(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textMuted.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTierHeader(String name, {required bool isRecommended}) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: MembershipTokens.headline(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isRecommended
                  ? MembershipTokens.accent
                  : MembershipTokens.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          if (isRecommended) ...[
            const SizedBox(height: 2),
            Container(
              height: 2,
              width: 16,
              decoration: BoxDecoration(
                color: MembershipTokens.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureRow(MatrixFeature feature) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: MembershipTokens.border.withOpacity(0.6),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12.0,
        vertical: 10.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Feature Name
          SizedBox(
            width: 118,
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                feature.title,
                style: MembershipTokens.body(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: MembershipTokens.textPrimary,
                  height: 1.25,
                ),
              ),
            ),
          ),
          // 4 Tier Columns
          Expanded(
            child: Row(
              children: [
                _buildCell(
                  feature.statusFor(MembershipTier.free),
                  isPro: false,
                ),
                _buildCell(
                  feature.statusFor(MembershipTier.plus),
                  isPro: false,
                ),
                _buildCell(
                  feature.statusFor(MembershipTier.pro),
                  isPro: true,
                ),
                _buildCell(
                  feature.statusFor(MembershipTier.ultra),
                  isPro: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(InclusionStatus status, {required bool isPro}) {
    Widget iconWidget;
    switch (status) {
      case InclusionStatus.included:
        iconWidget = Icon(
          Icons.check,
          size: 17,
          color: isPro ? MembershipTokens.accent : MembershipTokens.textPrimary,
        );
        break;
      case InclusionStatus.planned:
        iconWidget = const Icon(
          Icons.schedule,
          size: 17,
          color: MembershipTokens.accent,
        );
        break;
      case InclusionStatus.notIncluded:
        iconWidget = Text(
          '—',
          style: MembershipTokens.mono(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: MembershipTokens.textMuted,
          ),
          textAlign: TextAlign.center,
        );
        break;
    }

    return Expanded(
      child: Center(
        child: iconWidget,
      ),
    );
  }
}
