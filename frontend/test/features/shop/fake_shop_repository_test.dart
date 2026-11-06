import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/shop/data/datasources/fake_shop_local_data_source.dart';
import 'package:health_ai_app/features/shop/data/repositories/fake_shop_repository_impl.dart';
import 'package:health_ai_app/features/shop/domain/entities/product_query.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_product.dart';
import 'package:health_ai_app/features/shop/domain/failures/shop_failure.dart';

void main() {
  late FakeShopRepositoryImpl repository;

  setUp(() {
    repository = FakeShopRepositoryImpl(
      defaultDelay: Duration.zero, // Zero delay for deterministic unit tests
      scenario: FakeShopScenario.normal,
    );
  });

  group('FakeShopRepositoryImpl — Datasets & Metadata', () {
    test('loads 5 categories and 6 collections', () async {
      final categories = await repository.getCategories();
      final collections = await repository.getCollections();

      expect(categories.length, 5);
      expect(collections.length, 6);
      expect(categories.map((c) => c.id),
          contains(FakeShopLocalDataSource.categoryGear));
      expect(collections.map((c) => c.id),
          contains(FakeShopLocalDataSource.collectionHomeStarter));
    });

    test(
        'default catalog contains exactly 80 active products partitioned across 5 categories',
        () async {
      final page = await repository.getProducts(ProductQuery(pageSize: 100));
      expect(page.items.length, 80);

      final gear = page.items
          .where((p) => p.categoryId == FakeShopLocalDataSource.categoryGear);
      final apparel = page.items
          .where((p) => p.categoryId == FakeShopLocalDataSource.categoryApparel);
      final food = page.items.where(
          (p) => p.categoryId == FakeShopLocalDataSource.categoryFoodBeverage);
      final supp = page.items.where(
          (p) => p.categoryId == FakeShopLocalDataSource.categorySupplements);
      final rec = page.items.where((p) =>
          p.categoryId == FakeShopLocalDataSource.categoryRecoveryLifestyle);

      expect(gear.length, 16);
      expect(apparel.length, 20);
      expect(food.length, 24);
      expect(supp.length, 8);
      expect(rec.length, 12);
    });

    test('all mock items have isDemo=true and valid contentProvenance',
        () async {
      final page = await repository.getProducts(ProductQuery(pageSize: 50));
      for (final product in page.items) {
        expect(product.isDemo, isTrue);
        expect(product.contentProvenance.sourceName, isNotEmpty);
        expect(product.contentProvenance.rightsBasis, isNotEmpty);
      }
    });
  });

  group('FakeShopRepositoryImpl — Vietnamese Search & Filters', () {
    test('searches case-insensitively with diacritics', () async {
      final page =
          await repository.getProducts(ProductQuery(query: 'Bình lắc'));
      expect(page.items, isNotEmpty);
      expect(
          page.items.any(
              (p) => p.title.contains('Shaker') || p.title.contains('Bình')),
          isTrue);
    });

    test('searches without diacritics and matches diacritic titles', () async {
      final page =
          await repository.getProducts(ProductQuery(query: 'binh lac'));
      expect(page.items, isNotEmpty);
      expect(page.items.any((p) => p.id == 'prod_mp_01'), isTrue);
    });

    test('properly normalizes letter đ and Đ', () async {
      // 'đai' vs 'dai'
      final pageD =
          await repository.getProducts(ProductQuery(query: 'đai lưng'));
      final pageNoD =
          await repository.getProducts(ProductQuery(query: 'dai lung'));

      expect(pageD.items, isNotEmpty);
      expect(pageNoD.items, isNotEmpty);
      expect(pageD.items.length, pageNoD.items.length);
      expect(pageD.items.any((p) => p.title.contains('Đai')), isTrue);
    });

    test('combines query, category, and collection with AND logic', () async {
      final query = ProductQuery(
        query: 'straps',
        categoryId: FakeShopLocalDataSource.categoryGear,
        collectionId: FakeShopLocalDataSource.collectionHomeStarter,
      );

      final page = await repository.getProducts(query);
      expect(page.items, isNotEmpty);
      for (final p in page.items) {
        expect(p.categoryId, FakeShopLocalDataSource.categoryGear);
        expect(p.collectionIds,
            contains(FakeShopLocalDataSource.collectionHomeStarter));
      }
    });

    test('clearing a filter returns full unfiltered set', () async {
      final filteredQuery = ProductQuery(
          categoryId: FakeShopLocalDataSource.categoryGear);
      final filteredPage = await repository.getProducts(filteredQuery);
      expect(filteredPage.items.length, 16);

      final clearedQuery = filteredQuery.copyWith(categoryId: null);
      final allPage = await repository.getProducts(clearedQuery);
      expect(allPage.items.length, 20); // first page of 20
    });
  });

  group('FakeShopRepositoryImpl — Pagination & Opaque Cursors', () {
    test('paginates 80 products across 4 pages with zero ID overlap', () async {
      // Page 1: pageSize 20
      final page1 = await repository.getProducts(ProductQuery(pageSize: 20));
      expect(page1.items.length, 20);
      expect(page1.hasMore, isTrue);
      expect(page1.nextCursor, isNotNull);

      // Page 2: query with nextCursor
      final page2 = await repository.getProducts(
          ProductQuery(pageSize: 20, cursor: page1.nextCursor));
      expect(page2.items.length, 20);
      expect(page2.hasMore, isTrue);
      expect(page2.nextCursor, isNotNull);

      // Page 3
      final page3 = await repository.getProducts(
          ProductQuery(pageSize: 20, cursor: page2.nextCursor));
      expect(page3.items.length, 20);
      expect(page3.hasMore, isTrue);
      expect(page3.nextCursor, isNotNull);

      // Page 4: final page
      final page4 = await repository.getProducts(
          ProductQuery(pageSize: 20, cursor: page3.nextCursor));
      expect(page4.items.length, 20);
      expect(page4.hasMore, isFalse);
      expect(page4.nextCursor, isNull);

      // Ensure no overlapping IDs across all 4 pages
      final allIds = <String>{};
      for (final p in [page1, page2, page3, page4]) {
        final pIds = p.items.map((x) => x.id).toSet();
        expect(allIds.intersection(pIds), isEmpty);
        allIds.addAll(pIds);
      }
      expect(allIds.length, 80);
    });

    test('throws ShopInvalidCursorFailure on corrupted or malformed cursor',
        () async {
      final query = ProductQuery(cursor: 'not_a_valid_base64_cursor');
      expect(
        repository.getProducts(query),
        throwsA(isA<ShopInvalidCursorFailure>()),
      );
    });

    test(
        'throws ShopInvalidCursorFailure when cursor is used on mismatched query',
        () async {
      // Get cursor for categoryTrainingGear
      final page1 = await repository.getProducts(
        ProductQuery(
            categoryId: FakeShopLocalDataSource.categoryTrainingGear,
            pageSize: 4),
      );
      final cursorFromCat1 = page1.nextCursor!;

      // Attempt to reuse that cursor on categoryMealPrep
      final mismatchedQuery = ProductQuery(
        categoryId: FakeShopLocalDataSource.categoryMealPrep,
        cursor: cursorFromCat1,
      );

      expect(
        repository.getProducts(mismatchedQuery),
        throwsA(isA<ShopInvalidCursorFailure>()),
      );
    });

    test('supports extended fixture dataset across 3 pages', () async {
      // Generate 45 items
      final extendedList = List.generate(45, (i) {
        return ShopProduct(
          id: 'ext_prod_$i',
          title: 'Extended Product $i',
          subtitle: 'Subtitle $i',
          categoryId: FakeShopLocalDataSource.categoryTrainingGear,
          description: 'Desc',
          editorialNote: 'Note',
          priceVnd: 100000 + i * 1000,
          sourceType: ProductSourceType.manualCurated,
          contentProvenance: FakeShopLocalDataSource.standardProvenance,
          availability: ProductAvailability.available,
          heroImageUrl: 'assets/images/home_shop_essentials.jpg',
          curatedOrder: i,
        );
      });

      repository.setProducts(extendedList);

      // Page 1
      final p1 = await repository.getProducts(ProductQuery(pageSize: 20));
      expect(p1.items.length, 20);
      expect(p1.hasMore, isTrue);

      // Page 2
      final p2 = await repository
          .getProducts(ProductQuery(pageSize: 20, cursor: p1.nextCursor));
      expect(p2.items.length, 20);
      expect(p2.hasMore, isTrue);

      // Page 3
      final p3 = await repository
          .getProducts(ProductQuery(pageSize: 20, cursor: p2.nextCursor));
      expect(p3.items.length, 5);
      expect(p3.hasMore, isFalse);
      expect(p3.nextCursor, isNull);
    });
  });

  group('FakeShopRepositoryImpl — Controllable Scenarios', () {
    test('empty scenario returns empty product page', () async {
      repository.scenario = FakeShopScenario.empty;
      final page = await repository.getProducts(ProductQuery());
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('firstPageError throws on first page, recovers when reset to normal',
        () async {
      repository.scenario = FakeShopScenario.firstPageError;
      await expectLater(
        repository.getProducts(ProductQuery()),
        throwsA(isA<ShopCatalogLoadFailure>()),
      );

      // Recover
      repository.scenario = FakeShopScenario.normal;
      final page = await repository.getProducts(ProductQuery());
      expect(page.items, isNotEmpty);
    });

    test(
        'nextPageError succeeds on page 1 and throws on page 2, then retries cleanly',
        () async {
      repository.scenario = FakeShopScenario.nextPageError;

      // Page 1 succeeds
      final p1 = await repository.getProducts(ProductQuery(pageSize: 20));
      expect(p1.items.length, 20);
      expect(p1.nextCursor, isNotNull);

      // Page 2 throws
      await expectLater(
        repository
            .getProducts(ProductQuery(pageSize: 20, cursor: p1.nextCursor)),
        throwsA(isA<ShopCatalogLoadFailure>()),
      );

      // Retry after resolving error scenario
      repository.scenario = FakeShopScenario.normal;
      final p2 = await repository
          .getProducts(ProductQuery(pageSize: 20, cursor: p1.nextCursor));
      expect(p2.items.length, 20);
      expect(p2.hasMore, isTrue);
    });
  });

  group('FakeShopRepositoryImpl — Product Details & Batch Fetching', () {
    test('getProductById returns product when found', () async {
      final product = await repository.getProductById('prod_tg_01');
      expect(product.id, 'prod_tg_01');
      expect(product.title, contains('Lifting Straps'));
    });

    test('getProductById throws ShopNotFoundFailure when ID does not exist',
        () async {
      expect(
        repository.getProductById('non_existent_id'),
        throwsA(isA<ShopNotFoundFailure>()),
      );
    });

    test('getProductsByIds preserves order and returns null for missing IDs',
        () async {
      final result = await repository.getProductsByIds([
        'prod_tg_01',
        'missing_id_alpha',
        'prod_mp_01',
        'missing_id_beta',
      ]);

      expect(result.length, 4);
      expect(result[0]?.id, 'prod_tg_01');
      expect(result[1], isNull); // Graceful placeholder for missing item
      expect(result[2]?.id, 'prod_mp_01');
      expect(result[3], isNull); // Graceful placeholder
    });
  });

  group('FakeShopRepositoryImpl — Out-of-Order Async Response Simulation', () {
    test('proves fake repository can model out-of-order completion', () async {
      final repoFast = FakeShopRepositoryImpl(
          defaultDelay: const Duration(milliseconds: 10));
      final repoSlow = FakeShopRepositoryImpl(
          defaultDelay: const Duration(milliseconds: 100));

      final orderOfCompletion = <String>[];

      // Request 1 starts first with slow delay
      final slowFuture =
          repoSlow.getProducts(ProductQuery(query: 'slow')).then((_) {
        orderOfCompletion.add('slow_request_finished');
      });

      // Request 2 starts second with fast delay
      final fastFuture =
          repoFast.getProducts(ProductQuery(query: 'fast')).then((_) {
        orderOfCompletion.add('fast_request_finished');
      });

      await Future.wait([slowFuture, fastFuture]);

      // Verify that fast request completed before the earlier slow request
      expect(orderOfCompletion,
          ['fast_request_finished', 'slow_request_finished']);
    });
  });
}
