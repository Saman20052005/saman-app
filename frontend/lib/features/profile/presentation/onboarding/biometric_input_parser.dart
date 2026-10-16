/// Parser and validator for onboarding biometric inputs (age, height, weight).
class BiometricInputParser {
  BiometricInputParser._();

  /// Parses and validates a decimal string for height or weight.
  ///
  /// Requirements:
  /// - Accepts single '.' or ',' decimal separator.
  /// - Rejects mixed separators (e.g. "1,750.5").
  /// - Rejects unfinished typing (e.g. "72.", "175,").
  /// - Rejects multiple separators (e.g. "72..5").
  /// - Rejects values <= 0, NaN, Infinity, negative or alphabetic input.
  /// - Preserves exact precision (no rounding or truncating).
  static double? parseValidBiometric(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Reject unfinished trailing separator
    if (trimmed.endsWith('.') || trimmed.endsWith(',')) {
      return null;
    }

    // Reject mixed separators
    if (trimmed.contains('.') && trimmed.contains(',')) {
      return null;
    }

    // Reject multiple separators
    final dotCount = '.'.allMatches(trimmed).length;
    final commaCount = ','.allMatches(trimmed).length;
    if (dotCount > 1 || commaCount > 1) {
      return null;
    }

    // Normalize ',' to '.'
    final normalized = trimmed.replaceAll(',', '.');

    // Strict regex check: only digits, optional single decimal point and digits
    final validNumberRegex = RegExp(r'^\d+(\.\d+)?$');
    if (!validNumberRegex.hasMatch(normalized)) {
      return null;
    }

    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite || value <= 0) {
      return null;
    }

    return value;
  }

  /// Parses and validates age input: integer strictly between 13 and 120.
  static int? parseValidAge(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final digitsOnlyRegex = RegExp(r'^\d+$');
    if (!digitsOnlyRegex.hasMatch(trimmed)) {
      return null;
    }

    final value = int.tryParse(trimmed);
    if (value == null || value < 13 || value > 120) {
      return null;
    }

    return value;
  }

  /// Formats a biometric value for display, preferring raw entered text when valid.
  static String formatBiometric(double? value, {String? rawText}) {
    if (rawText != null && rawText.trim().isNotEmpty) {
      final parsed = parseValidBiometric(rawText);
      if (parsed != null) {
        return rawText.trim();
      }
    }
    if (value == null) return '';
    if (value % 1 == 0) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}
