import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/features/shop/data/repositories/fake_shop_repository_impl.dart';
import 'package:health_ai_app/features/shop/data/repositories/remote_shop_repository.dart';
import 'package:health_ai_app/features/shop/domain/entities/product_query.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_product.dart';
import 'package:health_ai_app/features/shop/domain/failures/shop_failure.dart';
import 'package:health_ai_app/features/shop/presentation/providers/shop_providers.dart';
import 'package:health_ai_app/services/api_client.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  _ScriptedAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(dynamic data, {int statusCode = 200}) {
  final encoded = jsonEncode(data);
  return ResponseBody.fromString(
    encoded,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group('RemoteShopRepository — Contract & Data Mapping', () {
    late Dio testDio;
    late RemoteShopRepository repo;

    setUp(() {
      testDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      repo = RemoteShopRepository(dio: testDio, baseUrl: 'http://127.0.0.1:8000');
    });

    test('getCategories fetches and maps category list correctly', () async {
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        expect(options.path, equals('http://127.0.0.1:8000/api/shop/categories'));
        return _jsonResponse([
          {
            'id': 'cat_training_gear',
            'name': 'Dụng cụ tập luyện',
            'slug': 'training-gear',
            'iconAsset': 'assets/icons/dumbbell.svg',
            'sortOrder': 1,
          },
          {
            'id': 'cat_recovery_tools',
            'name': 'Dụng cụ phục hồi',
            'slug': 'recovery-tools',
            'iconAsset': 'assets/icons/recovery.svg',
            'sortOrder': 2,
          },
        ]);
      });

      final categories = await repo.getCategories();

      expect(categories.length, equals(2));
      expect(categories[0].id, equals('cat_training_gear'));
      expect(categories[0].name, equals('Dụng cụ tập luyện'));
      expect(categories[0].sortOrder, equals(1));
      expect(categories[1].id, equals('cat_recovery_tools'));
    });

    test('getCollections fetches and maps collection list correctly', () async {
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        expect(options.path, equals('http://127.0.0.1:8000/api/shop/collections'));
        return _jsonResponse([
          {
            'id': 'col_home_starter',
            'title': 'Bắt đầu tập tại nhà',
            'subtitle': 'Tối ưu không gian nhỏ',
            'description': 'Trang bị tối thiểu hiệu quả tối đa',
            'bannerImageUrl': 'assets/images/workout.jpg',
            'isFeatured': true,
            'sortOrder': 1,
          },
        ]);
      });

      final collections = await repo.getCollections();

      expect(collections.length, equals(1));
      expect(collections[0].id, equals('col_home_starter'));
      expect(collections[0].isFeatured, isTrue);
    });

    test('getProducts sends query parameters and maps paginated page', () async {
      RequestOptions? capturedOptions;
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        capturedOptions = options;
        return _jsonResponse({
          'items': [
            {
              'id': 'prod_tg_01',
              'title': 'Lifting Straps Cotton Heavy-Duty',
              'subtitle': 'Dây kéo lưng',
              'categoryId': 'cat_training_gear',
              'collectionIds': ['col_home_starter'],
              'badge': 'Curated',
              'description': 'Mô tả chi tiết',
              'editorialNote': 'Ghi chú biên tập',
              'priceVnd': 185000,
              'priceUpdatedAt': '2026-10-20T00:00:00.000Z',
              'sellerName': 'Saman Official Gear',
              'sourceType': 'internalBrand',
              'isDemo': true,
              'contentProvenance': {
                'sourceName': 'Saman Studio',
                'rightsBasis': 'CC0',
                'evidenceRef': 'DOC-01',
                'isMissingProof': false,
              },
              'availability': 'available',
              'heroImageUrl': 'assets/images/shop/straps.jpg',
              'galleryImageUrls': [],
              'specifications': {'Chất liệu': 'Cotton'},
              'shopeeUrl': 'https://shopee.vn/item-1',
              'curatedOrder': 1,
            }
          ],
          'nextCursor': 'v1:c2lnbmF0dXJl:20',
          'hasMore': true,
        });
      });

      final page = await repo.getProducts(ProductQuery(
        query: 'straps',
        categoryId: 'cat_training_gear',
        collectionId: 'col_home_starter',
        pageSize: 15,
        cursor: 'prev_cursor_token',
      ));

      expect(capturedOptions?.queryParameters['query'], equals('straps'));
      expect(capturedOptions?.queryParameters['categoryId'], equals('cat_training_gear'));
      expect(capturedOptions?.queryParameters['collectionId'], equals('col_home_starter'));
      expect(capturedOptions?.queryParameters['pageSize'], equals(15));
      expect(capturedOptions?.queryParameters['cursor'], equals('prev_cursor_token'));

      expect(page.items.length, equals(1));
      expect(page.items[0].id, equals('prod_tg_01'));
      expect(page.items[0].priceVnd, equals(185000));
      expect(page.items[0].priceUpdatedAt?.isUtc, isTrue);
      expect(page.items[0].availability, equals(ProductAvailability.available));
      expect(page.nextCursor, equals('v1:c2lnbmF0dXJl:20'));
      expect(page.hasMore, isTrue);
    });

    test('getProductById maps full details and nullable price correctly', () async {
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        return _jsonResponse({
          'id': 'prod_tg_06',
          'title': 'Wrist Wraps Đôi Băng Quấn Cổ Tay',
          'subtitle': 'Băng nẹp cố định',
          'categoryId': 'cat_training_gear',
          'collectionIds': [],
          'description': 'Mô tả',
          'editorialNote': 'Ghi chú',
          'priceVnd': null, // Null price fixture
          'priceUpdatedAt': null,
          'sellerName': 'Aolikes Store',
          'sourceType': 'affiliatePartner',
          'isDemo': true,
          'contentProvenance': {
            'sourceName': 'Saman Studio',
            'rightsBasis': 'CC0',
            'isMissingProof': false,
          },
          'availability': 'available',
          'heroImageUrl': 'assets/images/shop/wraps.jpg',
          'curatedOrder': 6,
        });
      });

      final product = await repo.getProductById('prod_tg_06');

      expect(product.id, equals('prod_tg_06'));
      expect(product.priceVnd, isNull);
      expect(product.priceUpdatedAt, isNull);
      expect(product.sourceType, equals(ProductSourceType.affiliatePartner));
      expect(product.isDemo, isTrue);
    });

    test('getProductById throws ShopNotFoundFailure on 404', () async {
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        return _jsonResponse(
          {'detail': {'code': 'NOT_FOUND', 'message': 'Product not found'}},
          statusCode: 404,
        );
      });

      expect(
        () => repo.getProductById('non_existent_id'),
        throwsA(isA<ShopNotFoundFailure>().having((f) => f.productId, 'productId', 'non_existent_id')),
      );
    });

    test('getProductsByIds preserves order and leaves null for missing/hidden items', () async {
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        expect(options.path, equals('http://127.0.0.1:8000/api/shop/products/batch'));
        final body = options.data as Map;
        expect(body['ids'], equals(['prod_tg_01', 'missing_id', 'prod_tg_02']));

        return _jsonResponse({
          'items': [
            {
              'id': 'prod_tg_01',
              'title': 'Lifting Straps',
              'subtitle': 'Sub',
              'categoryId': 'cat_training_gear',
              'description': 'Desc',
              'editorialNote': 'Note',
              'sourceType': 'internalBrand',
              'contentProvenance': {'sourceName': 'Saman', 'rightsBasis': 'CC0', 'isMissingProof': false},
              'availability': 'available',
              'heroImageUrl': 'assets/img1.jpg',
            },
            null, // missing / discontinued in backend
            {
              'id': 'prod_tg_02',
              'title': 'Figure 8 Straps',
              'subtitle': 'Sub',
              'categoryId': 'cat_training_gear',
              'description': 'Desc',
              'editorialNote': 'Note',
              'sourceType': 'affiliatePartner',
              'contentProvenance': {'sourceName': 'Saman', 'rightsBasis': 'CC0', 'isMissingProof': false},
              'availability': 'available',
              'heroImageUrl': 'assets/img2.jpg',
            },
          ]
        });
      });

      final result = await repo.getProductsByIds(['prod_tg_01', 'missing_id', 'prod_tg_02']);

      expect(result.length, equals(3));
      expect(result[0]?.id, equals('prod_tg_01'));
      expect(result[1], isNull); // Preserved null placeholder for Saved screen!
      expect(result[2]?.id, equals('prod_tg_02'));
    });

    test('maps 400 INVALID_CURSOR to ShopInvalidCursorFailure', () async {
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        return _jsonResponse(
          {
            'detail': {
              'code': 'INVALID_CURSOR',
              'message': 'Cursor không hợp lệ',
              'cursor': 'bad_cursor_token',
            }
          },
          statusCode: 400,
        );
      });

      expect(
        () => repo.getProducts(ProductQuery(cursor: 'bad_cursor_token')),
        throwsA(isA<ShopInvalidCursorFailure>().having((f) => f.cursor, 'cursor', 'bad_cursor_token')),
      );
    });

    test('maps connection timeout to ShopCatalogLoadFailure', () async {
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      });

      expect(
        () => repo.getCategories(),
        throwsA(isA<ShopCatalogLoadFailure>().having(
          (f) => f.message,
          'message',
          contains('Timeout'),
        )),
      );
    });

    test('maps connection offline error to ShopCatalogLoadFailure', () async {
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      expect(
        () => repo.getCategories(),
        throwsA(isA<ShopCatalogLoadFailure>().having(
          (f) => f.message,
          'message',
          contains('Offline'),
        )),
      );
    });
  });

  group('Shop Dependency Injection (DI) & Fallback Protection', () {
    test('default configuration injects FakeShopRepositoryImpl (M1 Mode)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final repo = container.read(shopRepositoryProvider);
      expect(repo, isA<FakeShopRepositoryImpl>());
    });

    test('live mode enabled injects RemoteShopRepository', () {
      final container = ProviderContainer(
        overrides: [
          shopLiveModeEnabledProvider.overrideWithValue(true),
          shopRemoteBaseUrlProvider.overrideWithValue('http://127.0.0.1:8000'),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(shopRepositoryProvider);
      expect(repo, isA<RemoteShopRepository>());
    });

    test('live mode with empty baseUrl throws StateError explicitly', () {
      final container = ProviderContainer(
        overrides: [
          shopLiveModeEnabledProvider.overrideWithValue(true),
          shopRemoteBaseUrlProvider.overrideWithValue(''),
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(shopRepositoryProvider),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('chưa được cấu hình: thiếu BACKEND_URL'),
        )),
      );
    });

    test('live repository failure throws ShopFailure and NEVER silently falls back to fake', () async {
      final testDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      testDio.httpClientAdapter = _ScriptedAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      final container = ProviderContainer(
        overrides: [
          shopLiveModeEnabledProvider.overrideWithValue(true),
          shopRemoteBaseUrlProvider.overrideWithValue('http://127.0.0.1:8000'),
          dioProvider.overrideWithValue(testDio),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(shopRepositoryProvider);
      expect(repo, isA<RemoteShopRepository>());

      // Calling getCategories MUST throw ShopCatalogLoadFailure and NOT silently return fake categories!
      expect(
        () => repo.getCategories(),
        throwsA(isA<ShopCatalogLoadFailure>()),
      );
    });
  });
}
