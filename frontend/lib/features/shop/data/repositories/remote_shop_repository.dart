import 'package:dio/dio.dart';

import '../../../../config/api_config.dart';
import '../../domain/entities/content_provenance.dart';
import '../../domain/entities/product_page.dart';
import '../../domain/entities/product_query.dart';
import '../../domain/entities/shop_category.dart';
import '../../domain/entities/shop_collection.dart';
import '../../domain/entities/shop_product.dart';
import '../../domain/failures/shop_failure.dart';
import '../../domain/repositories/shop_repository.dart';

/// Remote implementation of [ShopRepository] connecting to backend /api/shop REST endpoints.
class RemoteShopRepository implements ShopRepository {
  final Dio _dio;
  final String _baseUrl;

  RemoteShopRepository({
    required Dio dio,
    String? baseUrl,
  })  : _dio = dio,
        _baseUrl = (baseUrl ??
                (dio.options.baseUrl.isNotEmpty
                    ? dio.options.baseUrl
                    : ApiConfig.baseUrl))
            .replaceAll(RegExp(r'/+$'), '');

  @override
  Future<List<ShopCategory>> getCategories() async {
    try {
      final response = await _dio.get('$_baseUrl/api/shop/categories');
      final data = response.data;
      if (data is List) {
        return data
            .map((item) => _parseCategory(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      throw const ShopCatalogLoadFailure('Dữ liệu danh mục không đúng định dạng danh sách');
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is ShopFailure) rethrow;
      throw ShopCatalogLoadFailure('Không thể tải danh mục sản phẩm: $e');
    }
  }

  @override
  Future<List<ShopCollection>> getCollections() async {
    try {
      final response = await _dio.get('$_baseUrl/api/shop/collections');
      final data = response.data;
      if (data is List) {
        return data
            .map((item) => _parseCollection(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      throw const ShopCatalogLoadFailure('Dữ liệu bộ sưu tập không đúng định dạng danh sách');
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is ShopFailure) rethrow;
      throw ShopCatalogLoadFailure('Không thể tải bộ sưu tập: $e');
    }
  }

  @override
  Future<ProductPage> getProducts(ProductQuery query) async {
    try {
      final queryParams = <String, dynamic>{
        'pageSize': query.pageSize,
      };
      if (query.query != null && query.query!.trim().isNotEmpty) {
        queryParams['query'] = query.query!.trim();
      }
      if (query.categoryId != null && query.categoryId!.trim().isNotEmpty) {
        queryParams['categoryId'] = query.categoryId!.trim();
      }
      if (query.subcategoryId != null && query.subcategoryId!.trim().isNotEmpty) {
        queryParams['subcategoryId'] = query.subcategoryId!.trim();
      }
      if (query.collectionId != null && query.collectionId!.trim().isNotEmpty) {
        queryParams['collectionId'] = query.collectionId!.trim();
      }
      if (query.cursor != null && query.cursor!.trim().isNotEmpty) {
        queryParams['cursor'] = query.cursor!.trim();
      }

      final response = await _dio.get(
        '$_baseUrl/api/shop/products',
        queryParameters: queryParams,
      );

      final data = response.data;
      if (data is Map) {
        final rawItems = data['items'];
        if (rawItems is List) {
          final items = rawItems
              .map((it) => _parseProduct(Map<String, dynamic>.from(it as Map)))
              .toList();
          final nextCursor = data['nextCursor']?.toString();
          final hasMore = data['hasMore'] == true;
          return ProductPage(
            items: items,
            nextCursor: nextCursor,
            hasMore: hasMore,
          );
        }
      }
      throw const ShopCatalogLoadFailure('Dữ liệu sản phẩm trả về không hợp lệ');
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is ShopFailure) rethrow;
      throw ShopCatalogLoadFailure('Không thể nạp danh sách sản phẩm: $e');
    }
  }

  @override
  Future<ShopProduct> getProductById(String id) async {
    try {
      final response = await _dio.get('$_baseUrl/api/shop/products/$id');
      final data = response.data;
      if (data is Map) {
        return _parseProduct(Map<String, dynamic>.from(data));
      }
      throw ShopNotFoundFailure(id);
    } on DioException catch (e) {
      throw _mapDioError(e, id);
    } catch (e) {
      if (e is ShopFailure) rethrow;
      throw ShopCatalogLoadFailure('Không thể nạp chi tiết sản phẩm: $e');
    }
  }

  @override
  Future<List<ShopProduct?>> getProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final response = await _dio.post(
        '$_baseUrl/api/shop/products/batch',
        data: {'ids': ids},
      );
      final data = response.data;
      if (data is Map && data['items'] is List) {
        final list = data['items'] as List;
        return list.map((item) {
          if (item == null) return null;
          if (item is Map) {
            return _parseProduct(Map<String, dynamic>.from(item));
          }
          return null;
        }).toList();
      }
      throw const ShopCatalogLoadFailure('Dữ liệu batch products không đúng định dạng');
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is ShopFailure) rethrow;
      throw ShopCatalogLoadFailure('Lỗi nạp batch products: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // JSON Parsing Helpers
  // ──────────────────────────────────────────────────────────────────────────

  ShopCategory _parseCategory(Map<dynamic, dynamic> json) {
    return ShopCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      iconAsset: json['iconAsset'] as String,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  ShopCollection _parseCollection(Map<dynamic, dynamic> json) {
    return ShopCollection(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      description: json['description'] as String,
      bannerImageUrl: json['bannerImageUrl'] as String,
      isFeatured: json['isFeatured'] == true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  ShopProduct _parseProduct(Map<dynamic, dynamic> json) {
    final rawPrice = json['priceVnd'];
    final priceVnd = rawPrice != null ? (rawPrice as num).toInt() : null;

    DateTime? priceUpdatedAt;
    final rawDate = json['priceUpdatedAt'];
    if (rawDate != null) {
      priceUpdatedAt = DateTime.tryParse(rawDate.toString())?.toUtc();
    }

    final collectionIds = (json['collectionIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    final galleryImageUrls = (json['galleryImageUrls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    final rawSpecs = json['specifications'];
    final specifications = <String, String>{};
    if (rawSpecs is Map) {
      for (final entry in rawSpecs.entries) {
        specifications[entry.key.toString()] = entry.value.toString();
      }
    }

    return ShopProduct(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      categoryId: json['categoryId'] as String,
      collectionIds: collectionIds,
      productType: json['productType'] as String? ?? 'generic',
      subcategoryId: json['subcategoryId'] as String?,
      badge: json['badge'] as String?,
      description: json['description'] as String,
      editorialNote: json['editorialNote'] as String,
      priceVnd: priceVnd,
      priceUpdatedAt: priceUpdatedAt,
      sellerName: json['sellerName'] as String?,
      sourceType: _parseSourceType(json['sourceType']?.toString()),
      isDemo: json['isDemo'] == true,
      contentProvenance: _parseProvenance(json['contentProvenance'] as Map?),
      availability: _parseAvailability(json['availability']?.toString()),
      heroImageUrl: json['heroImageUrl'] as String,
      galleryImageUrls: galleryImageUrls,
      specifications: specifications,
      shopeeUrl: json['shopeeUrl'] as String?,
      curatedOrder: (json['curatedOrder'] as num?)?.toInt() ?? 0,
      equipmentAttributes:
          _parseEquipmentAttributes(json['equipmentAttributes'] as Map?),
      apparelAttributes:
          _parseApparelAttributes(json['apparelAttributes'] as Map?),
      foodAttributes: _parseFoodAttributes(json['foodAttributes'] as Map?),
      supplementAttributes:
          _parseSupplementAttributes(json['supplementAttributes'] as Map?),
      lifestyleAttributes:
          _parseLifestyleAttributes(json['lifestyleAttributes'] as Map?),
    );
  }

  EquipmentAttributes? _parseEquipmentAttributes(Map? m) {
    if (m == null) return null;
    return EquipmentAttributes(
      primaryMaterial: m['primaryMaterial']?.toString() ?? '',
      gripType: m['gripType']?.toString(),
      lengthCm: (m['lengthCm'] as num?)?.toDouble(),
      widthCm: (m['widthCm'] as num?)?.toDouble(),
      thicknessMm: (m['thicknessMm'] as num?)?.toDouble(),
      weightKg: (m['weightKg'] as num?)?.toDouble(),
      maxLoadCapacityKg: (m['maxLoadCapacityKg'] as num?)?.toDouble(),
      resistanceRange: m['resistanceRange']?.toString(),
      usageEnvironment: m['usageEnvironment']?.toString(),
    );
  }

  ApparelAttributes? _parseApparelAttributes(Map? m) {
    if (m == null) return null;
    final rawColors = m['colorSwatches'] as List<dynamic>? ?? [];
    final colors = rawColors.map((c) {
      if (c is Map) {
        return ApparelColorSwatch(
          name: c['name']?.toString() ?? '',
          hexColor: c['hexColor']?.toString() ?? '',
        );
      }
      return const ApparelColorSwatch(name: '', hexColor: '');
    }).toList();

    return ApparelAttributes(
      fabricComposition: m['fabricComposition']?.toString() ?? '',
      fitType: m['fitType']?.toString() ?? '',
      genderTarget: m['genderTarget']?.toString() ?? '',
      sizePreviewList: (m['sizePreviewList'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      colorSwatches: colors,
      technologyTags: (m['technologyTags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      careInstructions: (m['careInstructions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  MacroNutrients? _parseMacros(Map? m) {
    if (m == null) return null;
    return MacroNutrients(
      energyKcal: (m['energyKcal'] as num?)?.toInt(),
      proteinGrams: (m['proteinGrams'] as num?)?.toDouble(),
      carbohydratesGrams: (m['carbohydratesGrams'] as num?)?.toDouble(),
      totalFatGrams: (m['totalFatGrams'] as num?)?.toDouble(),
      saturatedFatGrams: (m['saturatedFatGrams'] as num?)?.toDouble(),
      dietaryFiberGrams: (m['dietaryFiberGrams'] as num?)?.toDouble(),
      sugarsGrams: (m['sugarsGrams'] as num?)?.toDouble(),
      sodiumMg: (m['sodiumMg'] as num?)?.toInt(),
    );
  }

  FoodAttributes? _parseFoodAttributes(Map? m) {
    if (m == null) return null;
    final allergenStatusStr = m['allergenStatus']?.toString();
    final allergenStatus = switch (allergenStatusStr) {
      'freeOfDeclaredAllergens' => AllergenStatus.freeOfDeclaredAllergens,
      'containsAllergens' => AllergenStatus.containsAllergens,
      _ => AllergenStatus.unknown,
    };

    return FoodAttributes(
      netWeightText: m['netWeightText']?.toString() ?? '',
      servingSizeText: m['servingSizeText']?.toString() ?? '',
      servingsPerContainer: (m['servingsPerContainer'] as num?)?.toInt(),
      perServingMacros: _parseMacros(m['perServingMacros'] as Map?),
      per100gMacros: _parseMacros(m['per100gMacros'] as Map?),
      ingredientsText: m['ingredientsText']?.toString() ?? '',
      allergenStatus: allergenStatus,
      allergenList: (m['allergenList'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      storageInstructions: m['storageInstructions']?.toString(),
      shelfLifeText: m['shelfLifeText']?.toString(),
    );
  }

  SupplementAttributes? _parseSupplementAttributes(Map? m) {
    if (m == null) return null;
    final formStr = m['form']?.toString();
    final form = switch (formStr) {
      'capsule' => SupplementForm.capsule,
      'tablet' => SupplementForm.tablet,
      'effervescentTablet' => SupplementForm.effervescentTablet,
      'liquid' => SupplementForm.liquid,
      _ => SupplementForm.powder,
    };

    final rawIngredients = m['activeIngredients'] as List<dynamic>? ?? [];
    final activeIngredients = rawIngredients.map((ai) {
      if (ai is Map) {
        return ActiveIngredient(
          name: ai['name']?.toString() ?? '',
          amountPerServing: ai['amountPerServing']?.toString() ?? '',
        );
      }
      return const ActiveIngredient(name: '', amountPerServing: '');
    }).toList();

    return SupplementAttributes(
      form: form,
      netWeightText: m['netWeightText']?.toString() ?? '',
      servingSizeText: m['servingSizeText']?.toString() ?? '',
      servingsPerContainer: (m['servingsPerContainer'] as num?)?.toInt() ?? 1,
      activeIngredients: activeIngredients,
      suggestedUse: m['suggestedUse']?.toString() ?? '',
      safetyAdvisory: m['safetyAdvisory']?.toString() ?? '',
      isProhibitedForMinors: m['isProhibitedForMinors'] == true,
    );
  }

  LifestyleAttributes? _parseLifestyleAttributes(Map? m) {
    if (m == null) return null;
    return LifestyleAttributes(
      primaryMaterial: m['primaryMaterial']?.toString() ?? '',
      capacityMl: (m['capacityMl'] as num?)?.toInt(),
      isDishwasherSafe: m['isDishwasherSafe'] == true,
      isMicrowaveSafe: m['isMicrowaveSafe'] == true,
      isBpaFree: m['isBpaFree'] != false,
      keepColdHours: (m['keepColdHours'] as num?)?.toInt(),
      keepHotHours: (m['keepHotHours'] as num?)?.toInt(),
      compartmentCount: (m['compartmentCount'] as num?)?.toInt(),
      includedAccessories: (m['includedAccessories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  ProductSourceType _parseSourceType(String? val) {
    return switch (val) {
      'internalBrand' => ProductSourceType.internalBrand,
      'affiliatePartner' => ProductSourceType.affiliatePartner,
      'merchantPartner' => ProductSourceType.merchantPartner,
      'manualCurated' => ProductSourceType.manualCurated,
      _ => ProductSourceType.manualCurated,
    };
  }

  ProductAvailability _parseAvailability(String? val) {
    return switch (val) {
      'available' => ProductAvailability.available,
      'unavailable' => ProductAvailability.unavailable,
      'discontinued' => ProductAvailability.discontinued,
      _ => ProductAvailability.unknown,
    };
  }

  ContentProvenance _parseProvenance(Map<dynamic, dynamic>? json) {
    if (json == null) {
      return const ContentProvenance(
        sourceName: 'Saman Editorial Desk',
        rightsBasis: 'Internal Curation',
        isMissingProof: true,
      );
    }
    return ContentProvenance(
      sourceName: json['sourceName']?.toString() ?? 'Saman Editorial Desk',
      rightsBasis: json['rightsBasis']?.toString() ?? 'Internal Curation',
      evidenceRef: json['evidenceRef']?.toString(),
      isMissingProof: json['isMissingProof'] == true,
    );
  }

  ShopFailure _mapDioError(DioException error, [String? id]) {
    if (error.response?.statusCode == 404) {
      return ShopNotFoundFailure(id ?? 'UNKNOWN');
    }
    if (error.response?.statusCode == 400) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) {
          final code = detail['code']?.toString();
          final message = detail['message']?.toString() ?? 'Yêu cầu không hợp lệ';
          if (code == 'INVALID_CURSOR') {
            final cursor = detail['cursor']?.toString() ?? '';
            return ShopInvalidCursorFailure(cursor, message);
          }
          if (code == 'INVALID_QUERY') {
            return ShopInvalidQueryFailure(message);
          }
        }
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const ShopCatalogLoadFailure(
        'Kết nối máy chủ quá thời gian quy định (Timeout)',
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return const ShopCatalogLoadFailure(
        'Không thể kết nối đến máy chủ Saman (Offline / Network Error)',
      );
    }
    return ShopCatalogLoadFailure(
      error.response?.data?['detail']?.toString() ??
          error.error?.toString() ??
          error.message ??
          'Không thể tải danh mục sản phẩm từ máy chủ',
    );
  }
}
