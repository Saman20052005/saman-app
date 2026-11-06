import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'food_image_manifest.dart';

/// Metadata attribution cho ảnh món ăn (bản quyền, tác giả, link nguồn, ghi chú crop/resize).
class FoodImageAttribution {
  final String id;
  final String name;
  final String group;
  final String type; // 'ai_generated' | 'wikimedia_commons'
  final String model;
  final String? fileTitle;
  final String sourceUrl;
  final String? directImageUrl;
  final String license;
  final String licenseUrl;
  final String author;
  final String attributionText;
  final bool isCroppedResized;
  final String modificationNote;

  const FoodImageAttribution({
    required this.id,
    required this.name,
    required this.group,
    required this.type,
    this.model = '',
    this.fileTitle,
    required this.sourceUrl,
    this.directImageUrl,
    required this.license,
    required this.licenseUrl,
    required this.author,
    required this.attributionText,
    this.isCroppedResized = true,
    required this.modificationNote,
  });

  factory FoodImageAttribution.fromJson(Map<String, dynamic> json) {
    return FoodImageAttribution(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      group: json['group'] as String? ?? 'Food',
      type: json['type'] as String? ?? 'ai_generated',
      model: json['model'] as String? ?? '',
      fileTitle: json['file_title'] as String?,
      sourceUrl: json['source_url'] as String? ?? '',
      directImageUrl: json['direct_image_url'] as String?,
      license: json['license'] as String? ?? 'Proprietary',
      licenseUrl: json['license_url'] as String? ?? 'https://saman.app/terms',
      author: json['author'] as String? ?? 'Saman App',
      attributionText: json['attribution_text'] as String? ?? '',
      isCroppedResized: json['is_cropped_resized'] as bool? ?? true,
      modificationNote: json['modification_note'] as String? ??
          'Ảnh gốc đã được cắt vuông (center crop 1:1) và nén tối ưu 384x384 px phục vụ hiển thị trong ứng dụng Saman.',
    );
  }

  bool get isAi => type == 'ai_generated';
  bool get isCommons => type == 'wikimedia_commons';
}

/// Service quản lý và tra cứu attribution của ảnh món ăn.
class FoodAttributionService {
  static Map<String, FoodImageAttribution>? _cache;

  /// Nạp toàn bộ dữ liệu attribution từ asset file `assets/images/nutrition/attributions.json`.
  static Future<Map<String, FoodImageAttribution>> loadAll() async {
    if (_cache != null) return _cache!;
    String? jsonStr;
    try {
      jsonStr = await rootBundle
          .loadString('assets/images/nutrition/attributions.json');
    } catch (_) {
      try {
        final f = File('assets/images/nutrition/attributions.json');
        if (f.existsSync()) {
          jsonStr = await f.readAsString();
        }
      } catch (_) {}
    }

    if (jsonStr == null) return {};

    try {
      final Map<String, dynamic> rawMap = json.decode(jsonStr);
      final result = <String, FoodImageAttribution>{};
      for (final entry in rawMap.entries) {
        if (entry.value is Map<String, dynamic>) {
          result[entry.key] = FoodImageAttribution.fromJson(
              entry.value as Map<String, dynamic>);
        }
      }
      _cache = result;
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Tra cứu attribution theo tên món tiếng Việt chuẩn.
  static Future<FoodImageAttribution?> getByName(String foodName) async {
    final id = kFoodImageIdByName[foodName.trim()];
    if (id == null) return null;
    final all = await loadAll();
    return all[id];
  }

  /// Tra cứu trực tiếp từ cache nếu đã nạp (đồng bộ).
  static FoodImageAttribution? getFromCacheByName(String foodName) {
    if (_cache == null) return null;
    final id = kFoodImageIdByName[foodName.trim()];
    if (id == null) return null;
    return _cache![id];
  }
}
