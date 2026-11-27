import 'package:flutter/widgets.dart';

/// Immutable data model describing a single step in a Saman Coach Marks tour.
@immutable
class CoachTourStep {
  const CoachTourStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.highlightPadding = const EdgeInsets.all(8),
    this.borderRadius = 16.0,
  });

  /// Key attached to the target widget to spotlight.
  final GlobalKey targetKey;

  /// Short headline displayed in the tooltip card.
  final String title;

  /// Concise 1-2 line explanation displayed below [title].
  final String description;

  /// Extra padding around the target widget's bounding box for the spotlight.
  final EdgeInsets highlightPadding;

  /// Corner radius of the spotlight cutout.
  final double borderRadius;
}
