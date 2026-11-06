import 'package:equatable/equatable.dart';

/// Represents origin, copyright basis, and audit evidence for product assets/content.
class ContentProvenance extends Equatable {
  final String sourceName;
  final String rightsBasis;
  final String? evidenceRef;
  final bool isMissingProof;

  const ContentProvenance({
    required this.sourceName,
    required this.rightsBasis,
    this.evidenceRef,
    required this.isMissingProof,
  });

  factory ContentProvenance.curatedMock({
    required String sourceName,
    String rightsBasis = 'Unsplash License',
    String? evidenceRef,
    bool isMissingProof = false,
  }) {
    return ContentProvenance(
      sourceName: sourceName,
      rightsBasis: rightsBasis,
      evidenceRef: evidenceRef,
      isMissingProof: isMissingProof,
    );
  }

  @override
  List<Object?> get props =>
      [sourceName, rightsBasis, evidenceRef, isMissingProof];
}
