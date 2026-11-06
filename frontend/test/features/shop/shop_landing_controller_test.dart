import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/features/shop/data/datasources/fake_shop_local_data_source.dart';
import 'package:health_ai_app/features/shop/data/repositories/fake_shop_repository_impl.dart';
import 'package:health_ai_app/features/shop/domain/entities/product_page.dart';
import 'package:health_ai_app/features/shop/domain/entities/product_query.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_category.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_collection.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_product.dart';
import 'package:health_ai_app/features/shop/domain/failures/shop_failure.dart';
import 'package:health_ai_app/features/shop/domain/repositories/shop_repository.dart';
import 'package:health_ai_app/features/shop/presentation/controllers/shop_landing_controller.dart';
import 'package:health_ai_app/features/shop/presentation/controllers/shop_landing_state.dart';

/// Test mock repository that allows controlled delayed responses and injection of arbitrary errors.
class MockControllableShopRepository implements ShopRepository {
  MockControllableShopRepository({
    required this.categories,
    required this.collections,
    required this.defaultProducts,
  });

  final List<ShopCategory> categories;
  final List<ShopCollection> collections;
  final List<ShopProduct> defaultProducts;

  Completer<ProductPage>? inFlightCompleter;
  bool shouldThrowFirstPage = false;
  bool shouldThrowNextPage = false;

  @override
  Future<List<ShopCategory>> getCategories() async => categories;

  @override
  Future<List<ShopCollection>> getCollections() async => collections;

  @override
  Future<ShopProduct> getProductById(String id) async =>
      defaultProducts.firstWhere((p) => p.id == id);

  @override
  Future<List<ShopProduct?>> getProductsByIds(List<String> ids) async =>
      ids.map((id) {
        try {
          return defaultProducts.firstWhere((p) => p.id == id);
        } catch (_) {
          return null;
        }
      }).toList();

  @override
  Future<ProductPage> getProducts(ProductQuery query) async {
    if (shouldThrowFirstPage && query.cursor == null) {
      throw const ShopCatalogLoadFailure('Simulated first page failure');
    }
    if (shouldThrowNextPage && query.cursor != null) {
      throw const ShopCatalogLoadFailure('Simulated next page failure');
    }

    if (inFlightCompleter != null) {
      return inFlightCompleter!.future;
    }

    // Default immediate slicing
    final offset = query.cursor != null ? 10 : 0;
    final items = defaultProducts.skip(offset).take(10).toList();
    final hasMore = offset + items.length < defaultProducts.length;
    final nextCursor = hasMore ? 'cursor_${offset + items.length}' : null;

    return ProductPage(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeShopRepositoryImpl fakeRepo;
  late ShopLandingController controller;

  setUp(() {
    fakeRepo = FakeShopRepositoryImpl(
      defaultDelay: Duration.zero,
      scenario: FakeShopScenario.normal,
    );
    controller = ShopLandingController(
      repository: fakeRepo,
      debounceDuration: const Duration(milliseconds: 50),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('ShopLandingController — Search, Filter & Debounce', () {
    test('initializes with metadata and first page loaded', () async {
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state.status, equals(ShopCatalogStatus.loaded));
      expect(controller.state.products.length, equals(20)); // default page size
      expect(controller.state.categories.length, equals(5));
      expect(controller.state.collections.length, equals(6));
      expect(controller.state.hasMore, isTrue);
    });

    testWidgets('debounces search input: chưa đủ debounce chưa request, đủ debounce gửi đúng query cuối', (tester) async {
      final ctrl = ShopLandingController(
        repository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 50),
      );
      await tester.pump();

      // 1. Chưa đủ debounce (30ms < 50ms) -> chưa request, query chưa đổi
      ctrl.onSearchQueryChanged('foa');
      await tester.pump(const Duration(milliseconds: 30));
      expect(ctrl.state.query.query, isNull);

      // 2. Gõ tiếp trước khi hết debounce -> debounce reset lại từ đầu
      ctrl.onSearchQueryChanged('foam');
      await tester.pump(const Duration(milliseconds: 30));
      // Tổng thời gian từ keystroke 2 là 30ms (< 50ms) -> vẫn chưa gửi
      expect(ctrl.state.query.query, isNull);

      // 3. Đủ debounce (thêm 25ms -> 55ms > 50ms) -> chỉ gửi đúng query cuối ('foam')
      await tester.pump(const Duration(milliseconds: 25));
      expect(ctrl.state.query.query, equals('foam'));
      expect(ctrl.state.status, equals(ShopCatalogStatus.loaded));
      expect(ctrl.state.products.isNotEmpty, isTrue);

      ctrl.dispose();
    });

    testWidgets('clearSearchQuery instantly resets query without delay', (tester) async {
      final ctrl = ShopLandingController(
        repository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 50),
      );
      await tester.pump();

      ctrl.onSearchQueryChanged('shaker');
      await tester.pump(const Duration(milliseconds: 60));
      expect(ctrl.state.query.query, equals('shaker'));

      // Search rỗng/clearSearchQuery reset ngay lập tức, không chờ debounce
      ctrl.clearSearchQuery();
      expect(ctrl.state.query.query, isNull);
      await tester.pump();
      expect(ctrl.state.products.length, equals(20));

      ctrl.dispose();
    });

    test('category filter updates catalog and resets pagination cursor', () async {
      await Future<void>.delayed(const Duration(milliseconds: 10));

      controller.onCategorySelected(FakeShopLocalDataSource.categoryRecoveryLifestyle);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.query.categoryId,
          equals(FakeShopLocalDataSource.categoryRecoveryLifestyle));
      expect(controller.state.products.length, equals(12));
      for (final p in controller.state.products) {
        expect(p.categoryId, equals(FakeShopLocalDataSource.categoryRecoveryLifestyle));
      }
    });

    test('collection filter toggles on and off cleanly', () async {
      await Future<void>.delayed(const Duration(milliseconds: 10));

      controller.onCollectionSelected(FakeShopLocalDataSource.collectionHomeStarter);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.query.collectionId,
          equals(FakeShopLocalDataSource.collectionHomeStarter));
      expect(controller.state.activeCollection?.id,
          equals(FakeShopLocalDataSource.collectionHomeStarter));

      // Tapping again deselects collection filter
      controller.onCollectionSelected(FakeShopLocalDataSource.collectionHomeStarter);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.query.collectionId, isNull);
      expect(controller.state.activeCollection, isNull);
    });

    test('resetFilters clears query, category, and collection', () async {
      await Future<void>.delayed(const Duration(milliseconds: 10));

      controller.onSearchQueryChanged('foam');
      controller.onCategorySelected(FakeShopLocalDataSource.categoryRecoveryTools);
      controller.onCollectionSelected(FakeShopLocalDataSource.collectionRecovery);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      controller.resetFilters();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.query.query, isNull);
      expect(controller.state.query.categoryId, isNull);
      expect(controller.state.query.collectionId, isNull);
      expect(controller.state.products.length, equals(20));
    });

    testWidgets('distinguishes between emptyCatalog and noSearchResults', (tester) async {
      final ctrl = ShopLandingController(
        repository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 50),
      );
      await tester.pump();

      // Search for non-existent keyword -> noSearchResults (sau debounce)
      ctrl.onSearchQueryChanged('tu_khoa_khong_ton_tai_xyz');
      await tester.pump(const Duration(milliseconds: 60));

      expect(ctrl.state.status, equals(ShopCatalogStatus.noSearchResults));
      expect(ctrl.state.products, isEmpty);

      // Đổi sang empty scenario và reset filters -> emptyCatalog
      fakeRepo.scenario = FakeShopScenario.empty;
      ctrl.resetFilters();
      await tester.pump();

      expect(ctrl.state.status, equals(ShopCatalogStatus.emptyCatalog));
      expect(ctrl.state.products, isEmpty);

      ctrl.dispose();
    });
  });

  group('ShopLandingController — Epoch & Concurrency Guarding', () {
    test('discards stale response when A is slow and B is fast', () async {
      final mockRepo = MockControllableShopRepository(
        categories: FakeShopLocalDataSource.defaultCategories,
        collections: FakeShopLocalDataSource.defaultCollections,
        defaultProducts: FakeShopLocalDataSource.generateDefaultProducts(),
      );

      final ctrl = ShopLandingController(
        repository: mockRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );

      // Let initial load finish
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 1. Initiate Request A with controlled slow completer
      final slowCompleterA = Completer<ProductPage>();
      mockRepo.inFlightCompleter = slowCompleterA;

      ctrl.onCategorySelected(FakeShopLocalDataSource.categoryRecoveryTools);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // 2. Initiate Request B with immediate response
      mockRepo.inFlightCompleter = null; // Next request completes immediately
      ctrl.onCategorySelected(FakeShopLocalDataSource.categoryMealPrep);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // At this point, Request B has finished and state reflects categoryMealPrep
      expect(ctrl.state.query.categoryId,
          equals(FakeShopLocalDataSource.categoryMealPrep));

      // 3. Now complete Request A late
      slowCompleterA.complete(ProductPage(
        items: [FakeShopLocalDataSource.generateDefaultProducts().first],
        nextCursor: null,
        hasMore: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Stale response A MUST NOT overwrite Request B!
      expect(ctrl.state.query.categoryId,
          equals(FakeShopLocalDataSource.categoryMealPrep));

      ctrl.dispose();
    });

    test('error arriving late from stale request does not overwrite fresh state', () async {
      final mockRepo = MockControllableShopRepository(
        categories: FakeShopLocalDataSource.defaultCategories,
        collections: FakeShopLocalDataSource.defaultCollections,
        defaultProducts: FakeShopLocalDataSource.generateDefaultProducts(),
      );

      final ctrl = ShopLandingController(
        repository: mockRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 1. Slow Request A
      final slowCompleterA = Completer<ProductPage>();
      mockRepo.inFlightCompleter = slowCompleterA;
      ctrl.onCategorySelected('cat1');

      // 2. Fast Request B
      mockRepo.inFlightCompleter = null;
      ctrl.onCategorySelected('cat2');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(ctrl.state.status, equals(ShopCatalogStatus.loaded));

      // 3. Complete A with an error
      slowCompleterA.completeError(
          const ShopCatalogLoadFailure('Stale error from request A'));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Stale error must be discarded; status remains loaded
      expect(ctrl.state.status, equals(ShopCatalogStatus.loaded));
      expect(ctrl.state.error, isNull);

      ctrl.dispose();
    });

    test('filter change during load more does NOT append stale items', () async {
      final mockRepo = MockControllableShopRepository(
        categories: FakeShopLocalDataSource.defaultCategories,
        collections: FakeShopLocalDataSource.defaultCollections,
        defaultProducts: FakeShopLocalDataSource.generateDefaultProducts(),
      );

      final ctrl = ShopLandingController(
        repository: mockRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(ctrl.state.products.length, equals(10));

      // Start load more with slow completer
      final slowLoadMore = Completer<ProductPage>();
      mockRepo.inFlightCompleter = slowLoadMore;
      ctrl.loadMore();
      expect(ctrl.state.status, equals(ShopCatalogStatus.loadingMore));

      // User changes category while load more is in-flight!
      mockRepo.inFlightCompleter = null;
      ctrl.onCategorySelected(FakeShopLocalDataSource.categoryRecoveryTools);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Now complete the stale load-more
      slowLoadMore.complete(ProductPage(
        items: [FakeShopLocalDataSource.generateDefaultProducts().last],
        nextCursor: null,
        hasMore: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Stale item must NOT be appended to new category!
      expect(ctrl.state.query.categoryId,
          equals(FakeShopLocalDataSource.categoryRecoveryTools));
      expect(ctrl.state.products.length, equals(10));

      ctrl.dispose();
    });

    test('blocks duplicate concurrent load-more requests', () async {
      final mockRepo = MockControllableShopRepository(
        categories: FakeShopLocalDataSource.defaultCategories,
        collections: FakeShopLocalDataSource.defaultCollections,
        defaultProducts: FakeShopLocalDataSource.generateDefaultProducts(),
      );

      final ctrl = ShopLandingController(
        repository: mockRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final slowCompleter = Completer<ProductPage>();
      mockRepo.inFlightCompleter = slowCompleter;

      ctrl.loadMore();
      expect(ctrl.state.status, equals(ShopCatalogStatus.loadingMore));

      // Attempt second load-more while first is still pending
      ctrl.loadMore();
      expect(ctrl.state.status, equals(ShopCatalogStatus.loadingMore));

      // Complete once
      mockRepo.inFlightCompleter = null;
      slowCompleter.complete(ProductPage(
        items: [FakeShopLocalDataSource.generateDefaultProducts().first],
        nextCursor: null,
        hasMore: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(ctrl.state.status, equals(ShopCatalogStatus.loaded));
      ctrl.dispose();
    });

    test('recovers from load-more error via retryLoadMore retaining cursor and items', () async {
      fakeRepo.scenario = FakeShopScenario.nextPageError;
      final ctrl = ShopLandingController(
        repository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ctrl.state.status, equals(ShopCatalogStatus.loaded));
      final initialCount = ctrl.state.products.length;
      final savedCursor = ctrl.state.nextCursor;

      // Attempt load more -> triggers nextPageError
      await ctrl.loadMore();
      expect(ctrl.state.status, equals(ShopCatalogStatus.loadMoreError));
      expect(ctrl.state.products.length, equals(initialCount)); // items preserved!
      expect(ctrl.state.nextCursor, equals(savedCursor)); // cursor preserved!

      // Reset repo to normal and retry
      fakeRepo.scenario = FakeShopScenario.normal;
      await ctrl.retryLoadMore();

      expect(ctrl.state.status, equals(ShopCatalogStatus.loaded));
      expect(ctrl.state.products.length, greaterThan(initialCount)); // successfully appended!
      ctrl.dispose();
    });

    test('recovers from first-page error via retryFirstPage', () async {
      fakeRepo.scenario = FakeShopScenario.firstPageError;
      final ctrl = ShopLandingController(
        repository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ctrl.state.status, equals(ShopCatalogStatus.firstPageError));
      expect(ctrl.state.products, isEmpty);

      // Reset repo scenario and retry
      fakeRepo.scenario = FakeShopScenario.normal;
      await ctrl.retryFirstPage();

      expect(ctrl.state.status, equals(ShopCatalogStatus.loaded));
      expect(ctrl.state.products.length, equals(20));
      ctrl.dispose();
    });

    test('dispose safely cancels pending debounce and ignores callbacks', () async {
      final ctrl = ShopLandingController(
        repository: fakeRepo,
        debounceDuration: const Duration(milliseconds: 50),
      );
      ctrl.onSearchQueryChanged('test');
      ctrl.dispose();

      // Wait beyond debounce duration
      await Future<void>.delayed(const Duration(milliseconds: 70));

      // No exception thrown after dispose
      expect(true, isTrue);
    });
  });
}
