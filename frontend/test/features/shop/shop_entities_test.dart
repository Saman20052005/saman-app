import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/shop/domain/entities/content_provenance.dart';
import 'package:health_ai_app/features/shop/domain/entities/product_page.dart';
import 'package:health_ai_app/features/shop/domain/entities/product_query.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_category.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_product.dart';
import 'package:health_ai_app/features/shop/domain/failures/shop_failure.dart';

void main() {
  group('ShopProduct & Domain Entities', () {
    test('instantiates valid ShopProduct with immutable collections and specs',
        () {
      final product = ShopProduct(
        id: 'p1',
        title: 'Title 1',
        subtitle: 'Sub 1',
        categoryId: 'cat1',
        collectionIds: const ['col1'],
        description: 'Desc',
        editorialNote: 'Note',
        priceVnd: 150000,
        priceUpdatedAt: DateTime(2026, 10, 25),
        sellerName: 'Shop A',
        sourceType: ProductSourceType.internalBrand,
        isDemo: true,
        contentProvenance:
            ContentProvenance.curatedMock(sourceName: 'Saman Studio'),
        availability: ProductAvailability.available,
        heroImageUrl: 'assets/hero.jpg',
        galleryImageUrls: const ['assets/gal1.jpg'],
        specifications: const {'Material': 'Steel'},
        shopeeUrl: 'https://shopee.vn/p1',
      );

      expect(product.id, 'p1');
      expect(product.hasShopeeUrl, isTrue);
      expect(product.isAvailable, isTrue);
      expect(product.priceVnd, 150000);

      // Verify immutability
      expect(() => product.collectionIds.add('new'), throwsUnsupportedError);
      expect(() => product.galleryImageUrls.add('new'), throwsUnsupportedError);
      expect(
          () => product.specifications['Key'] = 'Val', throwsUnsupportedError);
    });

    test('priceVnd cannot be negative or zero', () {
      expect(
        () => ShopProduct(
          id: 'p_neg',
          title: 'Negative',
          subtitle: 'Sub',
          categoryId: 'cat1',
          description: 'Desc',
          editorialNote: 'Note',
          priceVnd: -100,
          sourceType: ProductSourceType.internalBrand,
          contentProvenance: ContentProvenance.curatedMock(sourceName: 'Saman'),
          availability: ProductAvailability.available,
          heroImageUrl: 'img.jpg',
        ),
        throwsArgumentError,
      );

      expect(
        () => ShopProduct(
          id: 'p_zero',
          title: 'Zero',
          subtitle: 'Sub',
          categoryId: 'cat1',
          description: 'Desc',
          editorialNote: 'Note',
          priceVnd: 0,
          sourceType: ProductSourceType.internalBrand,
          contentProvenance: ContentProvenance.curatedMock(sourceName: 'Saman'),
          availability: ProductAvailability.available,
          heroImageUrl: 'img.jpg',
        ),
        throwsArgumentError,
      );
    });

    test('supports nullable priceVnd and null shopeeUrl without inconsistency',
        () {
      final product = ShopProduct(
        id: 'p_noprice',
        title: 'No price',
        subtitle: 'Sub',
        categoryId: 'cat1',
        description: 'Desc',
        editorialNote: 'Note',
        priceVnd: null,
        priceUpdatedAt: null,
        sourceType: ProductSourceType.manualCurated,
        contentProvenance: ContentProvenance.curatedMock(sourceName: 'Saman'),
        availability: ProductAvailability.available,
        heroImageUrl: 'img.jpg',
        shopeeUrl: null,
      );

      expect(product.priceVnd, isNull);
      expect(product.hasShopeeUrl, isFalse);
      expect(product.isAvailable,
          isTrue); // Available in catalog even if URL not yet wired
    });

    test(
        'availability distinguishes available, unavailable, discontinued, unknown',
        () {
      expect(ProductAvailability.values.length, 4);
    });
  });

  group('ProductQuery', () {
    test('validates positive pageSize', () {
      expect(() => ProductQuery(pageSize: 0), throwsArgumentError);
      expect(() => ProductQuery(pageSize: -5), throwsArgumentError);
    });

    test('copyWith distinguishes not passed vs passed null to clear', () {
      final query = ProductQuery(
        query: 'belt',
        categoryId: 'cat1',
        collectionId: 'col1',
        cursor: 'cursor123',
        pageSize: 15,
      );

      // 1. Not passing arguments preserves them
      final unchanged = query.copyWith();
      expect(unchanged.query, 'belt');
      expect(unchanged.categoryId, 'cat1');
      expect(unchanged.collectionId, 'col1');
      expect(unchanged.cursor, 'cursor123');
      expect(unchanged.pageSize, 15);

      // 2. Passing null explicitly clears them
      final cleared = query.copyWith(
        query: null,
        categoryId: null,
        collectionId: null,
        cursor: null,
      );
      expect(cleared.query, isNull);
      expect(cleared.categoryId, isNull);
      expect(cleared.collectionId, isNull);
      expect(cleared.cursor, isNull);
      expect(cleared.pageSize, 15);
    });

    test('toFirstPage and resetAll behave as expected', () {
      final query = ProductQuery(
        query: 'straps',
        categoryId: 'cat1',
        cursor: 'token',
      );

      final firstPage = query.toFirstPage();
      expect(firstPage.query, 'straps');
      expect(firstPage.categoryId, 'cat1');
      expect(firstPage.cursor, isNull);

      final reset = query.resetAll();
      expect(reset.query, isNull);
      expect(reset.categoryId, isNull);
      expect(reset.cursor, isNull);
    });
  });

  group('ProductPage', () {
    test('enforces hasMore is false when nextCursor is null', () {
      final page = ProductPage(
        items: const [],
        nextCursor: null,
        hasMore: true, // Should be overridden to false
      );
      expect(page.hasMore, isFalse);
    });

    test('creates empty page factory', () {
      final empty = ProductPage.empty();
      expect(empty.items, isEmpty);
      expect(empty.nextCursor, isNull);
      expect(empty.hasMore, isFalse);
    });
  });

  group('ShopFailure Hierarchy', () {
    test('preserves typed codes and properties without dynamic', () {
      const nf = ShopNotFoundFailure('prod_99');
      expect(nf.code, 'NOT_FOUND');
      expect(nf.productId, 'prod_99');

      const invCursor = ShopInvalidCursorFailure('bad_tok');
      expect(invCursor.code, 'INVALID_CURSOR');
      expect(invCursor.cursor, 'bad_tok');

      const catErr = ShopCatalogLoadFailure();
      expect(catErr.code, 'CATALOG_LOAD_ERROR');

      final storeErr = ShopStorageFailure('Disk full', Exception('I/O error'));
      expect(storeErr.code, 'STORAGE_ERROR');
      expect(storeErr.cause, isNotNull);

      const launchErr = ShopLauncherFailure('https://shopee.vn');
      expect(launchErr.code, 'LAUNCHER_ERROR');
      expect(launchErr.url, 'https://shopee.vn');
    });
  });

  group('Typed Attributes & Taxonomy Normalization', () {
    test('ShopCategory.normalizeCategoryId maps legacy IDs to canonical IDs', () {
      expect(ShopCategory.normalizeCategoryId(ShopCategory.catTrainingGear),
          ShopCategory.catGear);
      expect(ShopCategory.normalizeCategoryId(ShopCategory.catRecoveryTools),
          ShopCategory.catRecoveryLifestyle);
      expect(ShopCategory.normalizeCategoryId(ShopCategory.catMealPrepHydration),
          ShopCategory.catRecoveryLifestyle);
      // Canonical stays canonical
      expect(ShopCategory.normalizeCategoryId(ShopCategory.catApparel),
          ShopCategory.catApparel);
      expect(ShopCategory.normalizeCategoryId(ShopCategory.catSupplements),
          ShopCategory.catSupplements);
    });

    test('ProductQuery supports subcategoryId and preserves on copyWith', () {
      final q = ProductQuery(
        categoryId: ShopCategory.catFoodBeverage,
        subcategoryId: 'Bữa sáng tiện lợi',
      );
      expect(q.subcategoryId, 'Bữa sáng tiện lợi');

      final qPreserved = q.copyWith();
      expect(qPreserved.subcategoryId, 'Bữa sáng tiện lợi');

      final qCleared = q.copyWith(subcategoryId: null);
      expect(qCleared.subcategoryId, isNull);
    });

    test('EquipmentAttributes instantiates with typed properties', () {
      const eq = EquipmentAttributes(
        primaryMaterial: '100% Cotton',
        gripType: 'Neoprene',
        lengthCm: 60.0,
        thicknessMm: 4.0,
        maxLoadCapacityKg: 350.0,
      );
      expect(eq.primaryMaterial, '100% Cotton');
      expect(eq.lengthCm, 60.0);
      expect(eq.props, contains(350.0));
    });

    test('ApparelAttributes enforces immutable colors and sizes', () {
      final ap = ApparelAttributes(
        fabricComposition: '95% Modal, 5% Spandex',
        fitType: 'Slim-Fit',
        genderTarget: 'Men',
        sizePreviewList: const ['M', 'L', 'XL'],
        colorSwatches: const [
          ApparelColorSwatch(name: 'Black', hexColor: '#000000'),
        ],
      );
      expect(ap.sizePreviewList.length, 3);
      expect(() => ap.sizePreviewList.add('XXL'), throwsUnsupportedError);
      expect(() => ap.colorSwatches.add(
          const ApparelColorSwatch(name: 'White', hexColor: '#FFFFFF')),
          throwsUnsupportedError);
    });

    test('FoodAttributes preserves numerical 0 for sugars/macros', () {
      final food = FoodAttributes(
        netWeightText: '500g',
        servingSizeText: '40g',
        servingsPerContainer: 12,
        perServingMacros: const MacroNutrients(
          energyKcal: 150,
          proteinGrams: 5.0,
          carbohydratesGrams: 28.0,
          sugarsGrams: 0.0, // Numerical 0 must be preserved
        ),
        ingredientsText: '100% Yến mạch nguyên cám',
        allergenStatus: AllergenStatus.freeOfDeclaredAllergens,
      );
      expect(food.perServingMacros?.sugarsGrams, 0.0);
      expect(food.allergenStatus, AllergenStatus.freeOfDeclaredAllergens);
      expect(food.allergenList, isEmpty);
    });

    test('SupplementAttributes supports substantive forms and active ingredients', () {
      final supp = SupplementAttributes(
        form: SupplementForm.effervescentTablet,
        netWeightText: '80g',
        servingSizeText: '1 viên',
        servingsPerContainer: 20,
        activeIngredients: const [
          ActiveIngredient(name: 'Natri', amountPerServing: '300mg'),
          ActiveIngredient(name: 'Kali', amountPerServing: '150mg'),
        ],
        suggestedUse: 'Hòa tan 1 viên vào 500ml nước',
        safetyAdvisory: 'Không dùng quá 3 viên/ngày',
      );
      expect(supp.form, SupplementForm.effervescentTablet);
      expect(supp.activeIngredients.length, 2);
      expect(supp.activeIngredients.first.name, 'Natri');
    });

    test('LifestyleAttributes enforces immutable accessories and capacity', () {
      final life = LifestyleAttributes(
        primaryMaterial: 'Thép không gỉ 304',
        capacityMl: 750,
        isBpaFree: true,
        isDishwasherSafe: false,
        includedAccessories: const ['Quả cầu lắc lò xo'],
      );
      expect(life.capacityMl, 750);
      expect(life.isBpaFree, isTrue);
      expect(() => life.includedAccessories.add('Ống hút'),
          throwsUnsupportedError);
    });
  });
}
