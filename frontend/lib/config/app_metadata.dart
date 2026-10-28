import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppMetadata {
  AppMetadata._();

  static const String appName = 'Saman';
  static const String versionName = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
  static const String buildNumber = String.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: '1',
  );

  /// Display string for App Settings, e.g., "1.0.0 (1)"
  static String get versionDisplay {
    if (buildNumber.isNotEmpty && buildNumber != '0') {
      return '$versionName ($buildNumber)';
    }
    return versionName;
  }
}

/// Provider supplying the current app version string from metadata.
final appVersionProvider = Provider<String>((ref) {
  return AppMetadata.versionDisplay;
});

