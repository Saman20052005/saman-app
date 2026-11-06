import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:health_ai_app/features/shop/data/datasources/fake_shop_local_data_source.dart';
import 'package:health_ai_app/features/shop/data/services/external_shop_launcher.dart';
import 'package:health_ai_app/features/shop/data/services/shop_platform_dispatcher.dart';
import 'package:health_ai_app/features/shop/domain/entities/content_provenance.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_product.dart';
import 'package:health_ai_app/features/shop/domain/services/shop_launcher_contract.dart';
import 'package:health_ai_app/features/shop/domain/services/shop_url_policy.dart';

/// Test dispatcher recording calls and returning controllable results.
class MockShopPlatformDispatcher implements ShopPlatformDispatcher {
  int callCount = 0;
  Uri? lastDispatchedUri;
  LaunchMode? lastMode;

  bool returnValue = true;
  Exception? throwException;

  @override
  Future<bool> dispatchUrl(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    callCount++;
    lastDispatchedUri = uri;
    lastMode = mode;

    if (throwException != null) {
      throw throwException!;
    }
    return returnValue;
  }
}

void main() {
  group('ExternalShopLauncher — Execution & Boundary Protection', () {
    late MockShopPlatformDispatcher mockDispatcher;
    late ExternalShopLauncher launcher;

    setUp(() {
      mockDispatcher = MockShopPlatformDispatcher();
      launcher = ExternalShopLauncher(
        urlPolicy: const ShopUrlPolicy(),
        platformDispatcher: mockDispatcher,
      );
    });

    test('demo product with URL returns demo result and NEVER calls platform',
        () async {
      final demoProduct = ShopProduct(
        id: 'p_demo_1',
        title: 'Demo Item With URL',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.internalBrand,
        isDemo: true,
        contentProvenance: FakeShopLocalDataSource.standardProvenance,
        availability: ProductAvailability.available,
        heroImageUrl: 'img.png',
        shopeeUrl: 'https://shopee.vn/sample-item',
      );

      final result = await launcher.launch(demoProduct);
      expect(result.type, LauncherResultType.demo);
      expect(result.message, contains('Sản phẩm minh họa'));
      expect(result.targetUrl, 'https://shopee.vn/sample-item');
      expect(mockDispatcher.callCount, 0); // Strictly zero platform calls!
    });

    test('demo product with null URL returns demo result and NEVER calls platform',
        () async {
      final demoProductNoUrl = ShopProduct(
        id: 'p_demo_2',
        title: 'Demo Item Without URL',
        subtitle: 'Sub',
        categoryId: 'cat_nutrition',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.manualCurated,
        isDemo: true,
        contentProvenance: FakeShopLocalDataSource.standardProvenance,
        availability: ProductAvailability.available,
        heroImageUrl: 'img.png',
        shopeeUrl: null,
      );

      final result = await launcher.launch(demoProductNoUrl);
      expect(result.type, LauncherResultType.demo);
      expect(result.targetUrl, isNull);
      expect(mockDispatcher.callCount, 0);
    });

    test('real product with valid URL dispatches via platform exactly once with LaunchMode.externalApplication',
        () async {
      final realProduct = ShopProduct(
        id: 'p_real_1',
        title: 'Real Item',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: const ContentProvenance(
          sourceName: 'Brand Partner',
          rightsBasis: 'Partner Agreement',
          isMissingProof: false,
        ),
        availability: ProductAvailability.available,
        heroImageUrl: 'img.png',
        shopeeUrl: 'https://shopee.vn/product/matte-shaker-750ml?sp_atk=123',
      );

      final result = await launcher.launch(realProduct);
      expect(result.type, LauncherResultType.dispatched);
      expect(result.targetUrl,
          'https://shopee.vn/product/matte-shaker-750ml?sp_atk=123');
      expect(mockDispatcher.callCount, 1);
      expect(mockDispatcher.lastDispatchedUri.toString(),
          'https://shopee.vn/product/matte-shaker-750ml?sp_atk=123');
      expect(mockDispatcher.lastMode, LaunchMode.externalApplication);
    });

    test('real product when platform returns false yields typed failed outcome',
        () async {
      mockDispatcher.returnValue = false;

      final realProduct = ShopProduct(
        id: 'p_real_false',
        title: 'Real Item False',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: const ContentProvenance(
          sourceName: 'Brand Partner',
          rightsBasis: 'Partner Agreement',
          isMissingProof: false,
        ),
        availability: ProductAvailability.available,
        heroImageUrl: 'img.png',
        shopeeUrl: 'https://shopee.vn/valid-item',
      );

      final result = await launcher.launch(realProduct);
      expect(result.type, LauncherResultType.failed);
      expect(result.message, contains('Thiết bị không thể mở'));
      expect(mockDispatcher.callCount, 1);
    });

    test('real product when platform throws exception yields safe failed outcome without crashing',
        () async {
      mockDispatcher.throwException = Exception('Platform channel timeout');

      final realProduct = ShopProduct(
        id: 'p_real_exc',
        title: 'Real Item Exception',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: const ContentProvenance(
          sourceName: 'Brand Partner',
          rightsBasis: 'Partner Agreement',
          isMissingProof: false,
        ),
        availability: ProductAvailability.available,
        heroImageUrl: 'img.png',
        shopeeUrl: 'https://shopee.vn/valid-item',
      );

      final result = await launcher.launch(realProduct);
      expect(result.type, LauncherResultType.failed);
      expect(result.message, contains('Lỗi kết nối'));
      expect(mockDispatcher.callCount, 1);
    });

    test('real product missing URL returns failed and does not call platform',
        () async {
      final realMissingUrl = ShopProduct(
        id: 'p_real_no_url',
        title: 'Real Missing URL',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: const ContentProvenance(
          sourceName: 'Brand Partner',
          rightsBasis: 'Partner Agreement',
          isMissingProof: false,
        ),
        availability: ProductAvailability.available,
        heroImageUrl: 'img.png',
        shopeeUrl: null,
      );

      final result = await launcher.launch(realMissingUrl);
      expect(result.type, LauncherResultType.failed);
      expect(result.message, contains('chưa có liên kết'));
      expect(mockDispatcher.callCount, 0);
    });

    test('real product with invalid URL (HTTP or evil host) is rejected by policy before platform call',
        () async {
      final realEvilUrl = ShopProduct(
        id: 'p_real_evil',
        title: 'Real Evil URL',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: const ContentProvenance(
          sourceName: 'Brand Partner',
          rightsBasis: 'Partner Agreement',
          isMissingProof: false,
        ),
        availability: ProductAvailability.available,
        heroImageUrl: 'img.png',
        shopeeUrl: 'https://evilshopee.vn/phishing',
      );

      final result = await launcher.launch(realEvilUrl);
      expect(result.type, LauncherResultType.failed);
      expect(result.message, contains('chưa được phê duyệt'));
      expect(mockDispatcher.callCount, 0);
    });

    test('real product with discontinued or unavailable status does not dispatch',
        () async {
      final discontinuedProduct = ShopProduct(
        id: 'p_real_discontinued',
        title: 'Discontinued Real',
        subtitle: 'Sub',
        categoryId: 'cat_training',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: const ContentProvenance(
          sourceName: 'Brand Partner',
          rightsBasis: 'Partner Agreement',
          isMissingProof: false,
        ),
        availability: ProductAvailability.discontinued,
        heroImageUrl: 'img.png',
        shopeeUrl: 'https://shopee.vn/discontinued-item',
      );

      final result = await launcher.launch(discontinuedProduct);
      expect(result.type, LauncherResultType.failed);
      expect(result.message, contains('không khả dụng'));
      expect(mockDispatcher.callCount, 0);
    });

    test('canLaunch returns true only for valid approved HTTPS URLs', () async {
      expect(await launcher.canLaunch('https://shopee.vn/item'), isTrue);
      expect(await launcher.canLaunch('http://shopee.vn/item'), isFalse);
      expect(await launcher.canLaunch('https://evilshopee.vn/item'), isFalse);
      expect(await launcher.canLaunch('   '), isFalse);
    });
  });
}

