import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/features/shop/data/datasources/fake_shop_local_data_source.dart';
import 'package:health_ai_app/features/shop/data/repositories/fake_shop_repository_impl.dart';
import 'package:health_ai_app/features/shop/data/repositories/remote_shop_repository.dart';
import 'package:health_ai_app/features/shop/data/repositories/shared_preferences_shop_wishlist_repository.dart';
import 'package:health_ai_app/features/shop/data/services/external_shop_launcher.dart';
import 'package:health_ai_app/features/shop/data/services/fake_shop_launcher.dart';
import 'package:health_ai_app/features/shop/domain/entities/content_provenance.dart';
import 'package:health_ai_app/features/shop/domain/entities/shop_product.dart';
import 'package:health_ai_app/features/shop/domain/services/shop_launcher_contract.dart';
import 'package:health_ai_app/features/shop/presentation/providers/shop_providers.dart';

void main() {
  group('FakeShopLauncher', () {
    late FakeShopLauncher launcher;

    setUp(() {
      launcher = FakeShopLauncher();
    });

    test('returns demo result for demo products without calling OS', () async {
      final demoProduct = ShopProduct(
        id: 'p_demo',
        title: 'Demo Product',
        subtitle: 'Sub',
        categoryId: 'cat1',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.internalBrand,
        isDemo: true,
        contentProvenance: FakeShopLocalDataSource.standardProvenance,
        availability: ProductAvailability.available,
        heroImageUrl: 'img.jpg',
        shopeeUrl: 'https://shopee.vn/demo-item',
      );

      final result = await launcher.launch(demoProduct);
      expect(result.type, LauncherResultType.demo);
      expect(result.message, contains('Sản phẩm minh họa'));
      expect(result.targetUrl, 'https://shopee.vn/demo-item');
    });

    test('returns demo result even if demo product has null URL', () async {
      final demoProductNoUrl = ShopProduct(
        id: 'p_demo_no_url',
        title: 'Demo No URL',
        subtitle: 'Sub',
        categoryId: 'cat1',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.manualCurated,
        isDemo: true,
        contentProvenance: FakeShopLocalDataSource.standardProvenance,
        availability: ProductAvailability.available,
        heroImageUrl: 'img.jpg',
        shopeeUrl: null,
      );

      final result = await launcher.launch(demoProductNoUrl);
      expect(result.type, LauncherResultType.demo);
      expect(result.targetUrl, isNull);
    });

    test('dispatches real URL when isDemo is false', () async {
      final realProduct = ShopProduct(
        id: 'p_real',
        title: 'Real Product',
        subtitle: 'Sub',
        categoryId: 'cat1',
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
        heroImageUrl: 'img.jpg',
        shopeeUrl: 'https://shopee.vn/real-item-url',
      );

      final result = await launcher.launch(realProduct);
      expect(result.type, LauncherResultType.dispatched);
      expect(result.targetUrl, 'https://shopee.vn/real-item-url');
    });

    test('returns failed when non-demo product lacks shopeeUrl', () async {
      final realProductNoUrl = ShopProduct(
        id: 'p_real_no_url',
        title: 'Real No URL',
        subtitle: 'Sub',
        categoryId: 'cat1',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.affiliatePartner,
        isDemo: false,
        contentProvenance: FakeShopLocalDataSource.standardProvenance,
        availability: ProductAvailability.available,
        heroImageUrl: 'img.jpg',
        shopeeUrl: null,
      );

      final result = await launcher.launch(realProductNoUrl);
      expect(result.type, LauncherResultType.failed);
      expect(result.message, contains('chưa có liên kết'));
    });

    test('forceFail scenario returns failed result', () async {
      launcher.scenario = FakeLauncherScenario.forceFail;

      final product = ShopProduct(
        id: 'p_test',
        title: 'Test',
        subtitle: 'Sub',
        categoryId: 'cat1',
        description: 'Desc',
        editorialNote: 'Note',
        sourceType: ProductSourceType.internalBrand,
        contentProvenance: FakeShopLocalDataSource.standardProvenance,
        availability: ProductAvailability.available,
        heroImageUrl: 'img.jpg',
        shopeeUrl: 'https://shopee.vn/item',
      );

      final result = await launcher.launch(product);
      expect(result.type, LauncherResultType.failed);
      expect(result.message, contains('Không thể kết nối'));
      expect(await launcher.canLaunch('https://shopee.vn'), isFalse);
    });
  });

  group('Riverpod DI & Providers', () {
    late SharedPreferences mockPrefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockPrefs = await SharedPreferences.getInstance();
    });

    test('resolves default providers and external launcher', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
        ],
      );
      addTearDown(container.dispose);

      final shopRepo = container.read(shopRepositoryProvider);
      final wishlistRepo = container.read(shopWishlistRepositoryProvider);
      final launcher = container.read(shopLauncherProvider);

      expect(shopRepo, isA<FakeShopRepositoryImpl>());
      expect(wishlistRepo, isA<SharedPreferencesShopWishlistRepository>());
      expect(launcher, isA<ExternalShopLauncher>());
    });

    test(
        'live mode unconfigured throws explicit StateError instead of silently falling back to fake',
        () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          shopLiveModeEnabledProvider
              .overrideWithValue(true), // Request Live mode
          shopRemoteBaseUrlProvider.overrideWithValue(''), // Unconfigured live mode
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(shopRepositoryProvider),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('RemoteShopRepository chưa được cấu hình'),
          ),
        ),
      );
    });

    test('live mode configured injects RemoteShopRepository', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          shopLiveModeEnabledProvider.overrideWithValue(true),
          shopRemoteBaseUrlProvider.overrideWithValue('http://127.0.0.1:8000'),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(shopRepositoryProvider);
      expect(repo, isA<RemoteShopRepository>());
    });

    test('allows clean mock overrides in test container', () {
      final customFake = FakeShopRepositoryImpl(
        scenario: FakeShopScenario.empty,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          shopRepositoryProvider.overrideWithValue(customFake),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(shopRepositoryProvider);
      expect(repo, same(customFake));
    });
  });
}
