import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Performance tier classified from real on-device AI benchmark & RAM.
enum CvHardwareTier {
  optimal,
  standard,
  limited,
}

/// Immutable hardware & pose-benchmark snapshot measured on-device.
@immutable
class CvHardwareReport {
  const CvHardwareReport({
    required this.deviceModel,
    required this.manufacturer,
    required this.socHardware,
    required this.totalRamMb,
    required this.cpuCores,
    required this.androidSdk,
    required this.measuredFps,
    required this.avgInferenceMs,
    required this.framesRun,
    required this.tier,
    required this.acknowledged,
    required this.measuredAt,
  });

  final String deviceModel;
  final String manufacturer;
  final String socHardware;
  final int totalRamMb;
  final int cpuCores;
  final int androidSdk;
  final double measuredFps;
  final double avgInferenceMs;
  final int framesRun;
  final CvHardwareTier tier;
  final bool acknowledged;
  final DateTime measuredAt;

  CvHardwareReport copyWith({
    String? deviceModel,
    String? manufacturer,
    String? socHardware,
    int? totalRamMb,
    int? cpuCores,
    int? androidSdk,
    double? measuredFps,
    double? avgInferenceMs,
    int? framesRun,
    CvHardwareTier? tier,
    bool? acknowledged,
    DateTime? measuredAt,
  }) {
    return CvHardwareReport(
      deviceModel: deviceModel ?? this.deviceModel,
      manufacturer: manufacturer ?? this.manufacturer,
      socHardware: socHardware ?? this.socHardware,
      totalRamMb: totalRamMb ?? this.totalRamMb,
      cpuCores: cpuCores ?? this.cpuCores,
      androidSdk: androidSdk ?? this.androidSdk,
      measuredFps: measuredFps ?? this.measuredFps,
      avgInferenceMs: avgInferenceMs ?? this.avgInferenceMs,
      framesRun: framesRun ?? this.framesRun,
      tier: tier ?? this.tier,
      acknowledged: acknowledged ?? this.acknowledged,
      measuredAt: measuredAt ?? this.measuredAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceModel': deviceModel,
      'manufacturer': manufacturer,
      'socHardware': socHardware,
      'totalRamMb': totalRamMb,
      'cpuCores': cpuCores,
      'androidSdk': androidSdk,
      'measuredFps': measuredFps,
      'avgInferenceMs': avgInferenceMs,
      'framesRun': framesRun,
      'tier': tier.name,
      'acknowledged': acknowledged,
      'measuredAt': measuredAt.toIso8601String(),
    };
  }

  factory CvHardwareReport.fromJson(Map<String, dynamic> json) {
    final tierName = json['tier'] as String? ?? CvHardwareTier.standard.name;
    final parsedTier = CvHardwareTier.values.firstWhere(
      (e) => e.name == tierName,
      orElse: () => CvHardwareTier.standard,
    );
    final measuredAtRaw = json['measuredAt'] as String?;
    final parsedDate =
        measuredAtRaw != null ? DateTime.tryParse(measuredAtRaw) : null;

    return CvHardwareReport(
      deviceModel: (json['deviceModel'] as String?) ?? 'Unknown',
      manufacturer: (json['manufacturer'] as String?) ?? '',
      socHardware: (json['socHardware'] as String?) ?? 'Unknown',
      totalRamMb: (json['totalRamMb'] as num?)?.toInt() ?? 0,
      cpuCores: (json['cpuCores'] as num?)?.toInt() ?? 0,
      androidSdk: (json['androidSdk'] as num?)?.toInt() ?? 0,
      measuredFps: (json['measuredFps'] as num?)?.toDouble() ?? 0.0,
      avgInferenceMs: (json['avgInferenceMs'] as num?)?.toDouble() ?? 0.0,
      framesRun: (json['framesRun'] as num?)?.toInt() ?? 0,
      tier: parsedTier,
      acknowledged: json['acknowledged'] as bool? ?? false,
      measuredAt: parsedDate ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Abstract hardware & pose-benchmark probe for easy testing.
abstract class CvHardwareProbe {
  Future<Map<String, dynamic>?> getDeviceHardwareInfo();

  Future<Map<String, dynamic>?> runPoseBenchmark({int frameCount = 12});
}

/// Platform-channel probe talking to native Android Workout CV host.
class MethodChannelCvHardwareProbe implements CvHardwareProbe {
  const MethodChannelCvHardwareProbe({
    MethodChannel? methodChannel,
  }) : _methodChannel = methodChannel ?? _defaultMethodChannel;

  static const MethodChannel _defaultMethodChannel =
      MethodChannel('com.example.health_ai_app/workout_cv/method');

  final MethodChannel _methodChannel;

  @override
  Future<Map<String, dynamic>?> getDeviceHardwareInfo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getDeviceHardwareInfo',
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> runPoseBenchmark({int frameCount = 12}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'runPoseBenchmark',
        <String, dynamic>{'frameCount': frameCount},
      );
      return result;
    } catch (_) {
      return null;
    }
  }
}

/// Evaluates real device hardware + on-device AI FPS and caches the report.
class CvHardwareRadarService {
  CvHardwareRadarService({
    CvHardwareProbe? probe,
    Future<SharedPreferences> Function()? prefsLoader,
  })  : _probe = probe ?? const MethodChannelCvHardwareProbe(),
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String cacheKey = 'saman_cv_hardware_radar_v1';

  final CvHardwareProbe _probe;
  final Future<SharedPreferences> Function() _prefsLoader;

  /// Transparent 3-tier hardware classification based on real FPS & RAM.
  static CvHardwareTier classify({
    required double measuredFps,
    required int totalRamMb,
  }) {
    if (measuredFps < 8.0) {
      return CvHardwareTier.limited;
    }
    if (measuredFps >= 15.0 && (totalRamMb >= 3072 || totalRamMb == 0)) {
      return CvHardwareTier.optimal;
    }
    return CvHardwareTier.standard;
  }

  /// Loads the cached [CvHardwareReport] from [SharedPreferences], if present.
  Future<CvHardwareReport?> loadCachedReport() async {
    try {
      final prefs = await _prefsLoader();
      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CvHardwareReport.fromJson(decoded);
      }
      if (decoded is Map) {
        return CvHardwareReport.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns `true` when there is no cached report or it has not been acknowledged.
  Future<bool> shouldShowRadarSheet() async {
    final cached = await loadCachedReport();
    return cached == null || !cached.acknowledged;
  }

  /// Reads real device info, runs the pose benchmark, classifies, and caches.
  Future<CvHardwareReport> runEvaluation({int frameCount = 12}) async {
    final info = await _probe.getDeviceHardwareInfo() ?? const <String, dynamic>{};
    final benchmark = await _probe.runPoseBenchmark(frameCount: frameCount) ??
        const <String, dynamic>{};

    final deviceModel =
        (info['deviceModel'] as String?)?.trim().isNotEmpty == true
            ? (info['deviceModel'] as String).trim()
            : 'Unknown';
    final manufacturer = (info['manufacturer'] as String?)?.trim() ?? '';
    final socHardware =
        (info['socHardware'] as String?)?.trim().isNotEmpty == true
            ? (info['socHardware'] as String).trim()
            : 'Unknown';

    final rawRam = (info['totalRamMb'] as num?)?.toInt() ?? 0;
    final totalRamMb = rawRam < 0 ? 0 : rawRam;

    final rawCores = (info['cpuCores'] as num?)?.toInt() ?? 0;
    final cpuCores = rawCores < 0 ? 0 : rawCores;

    final rawSdk = (info['androidSdk'] as num?)?.toInt() ?? 0;
    final androidSdk = rawSdk < 0 ? 0 : rawSdk;

    final rawFps = (benchmark['measuredFps'] as num?)?.toDouble() ?? 0.0;
    final measuredFps = rawFps < 0.0 ? 0.0 : rawFps;

    final rawAvgMs = (benchmark['avgInferenceMs'] as num?)?.toDouble() ?? 0.0;
    final avgInferenceMs = rawAvgMs > 0.0
        ? rawAvgMs
        : (measuredFps > 0.0 ? 1000.0 / measuredFps : 0.0);

    final rawFrames = (benchmark['framesRun'] as num?)?.toInt() ?? 0;
    final framesRun = rawFrames < 0 ? 0 : rawFrames;

    final tier = classify(
      measuredFps: measuredFps,
      totalRamMb: totalRamMb,
    );

    final report = CvHardwareReport(
      deviceModel: deviceModel,
      manufacturer: manufacturer,
      socHardware: socHardware,
      totalRamMb: totalRamMb,
      cpuCores: cpuCores,
      androidSdk: androidSdk,
      measuredFps: measuredFps,
      avgInferenceMs: avgInferenceMs,
      framesRun: framesRun,
      tier: tier,
      acknowledged: false,
      measuredAt: DateTime.now(),
    );

    await _saveReport(report);
    return report;
  }

  /// Marks [report] as acknowledged and persists it to [SharedPreferences].
  Future<CvHardwareReport> markAcknowledged(CvHardwareReport report) async {
    final updated = report.copyWith(acknowledged: true);
    await _saveReport(updated);
    return updated;
  }

  Future<void> _saveReport(CvHardwareReport report) async {
    final prefs = await _prefsLoader();
    await prefs.setString(cacheKey, jsonEncode(report.toJson()));
  }
}
