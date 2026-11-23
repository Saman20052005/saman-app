import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/api_config.dart';
import '../../../../providers/profile_provider.dart';
import '../../../../services/api_client.dart';
import '../../domain/repositories/shop_repository.dart';
import '../../domain/repositories/shop_wishlist_repository.dart';
import '../../domain/services/shop_launcher_contract.dart';
import '../../data/repositories/fake_shop_repository_impl.dart';
import '../../data/repositories/remote_shop_repository.dart';
import '../../data/repositories/shared_preferences_shop_wishlist_repository.dart';
import '../../data/services/external_shop_launcher.dart';

/// Flag indicating whether the application should attempt connecting to live/dev remote backend.
/// Defaults to false (M1 Fake Mode). Can be enabled for dev runtime testing via
/// --dart-define=SHOP_REMOTE_ENABLED=true.
const bool kShopRemoteEnabledDefault =
    bool.fromEnvironment('SHOP_REMOTE_ENABLED', defaultValue: false);
const String kShopRemoteBaseUrlDefault =
    String.fromEnvironment('SHOP_REMOTE_BASE_URL', defaultValue: '');

final shopLiveModeEnabledProvider =
    Provider<bool>((ref) => kShopRemoteEnabledDefault);

/// Base URL provider for remote catalog API.
final shopRemoteBaseUrlProvider = Provider<String>((ref) {
  if (kShopRemoteBaseUrlDefault.isNotEmpty) {
    return kShopRemoteBaseUrlDefault;
  }
  return ApiConfig.baseUrl;
});

/// Central provider for Catalog repository.
/// In M1, injects `FakeShopRepositoryImpl`.
/// When live mode is requested, injects `RemoteShopRepository`.
/// When live is unconfigured (empty baseUrl), throws StateError explicitly.
/// Remote failures throw typed ShopFailure and NEVER silently fallback to fake catalog.
final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  final isLive = ref.watch(shopLiveModeEnabledProvider);
  if (!isLive) {
    return FakeShopRepositoryImpl();
  }

  final baseUrl = ref.watch(shopRemoteBaseUrlProvider);
  if (baseUrl.trim().isEmpty) {
    throw StateError(
      'RemoteShopRepository chưa được cấu hình: thiếu BACKEND_URL.',
    );
  }

  final dio = ref.watch(dioProvider);
  return RemoteShopRepository(dio: dio, baseUrl: baseUrl);
});

/// Central provider for Wishlist repository.
/// Injects SharedPreferences, dio, and dynamic auth state sync.
final shopWishlistRepositoryProvider = Provider<ShopWishlistRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final dio = ref.watch(dioProvider);
  final confirmedUserId =
      ref.watch(profileProvider.select((s) => s.confirmedUserId));
  final isAuthenticated =
      confirmedUserId != null && confirmedUserId.isNotEmpty;

  final repo = SharedPreferencesShopWishlistRepository(
    prefs,
    dio: dio,
    syncEnabled: isAuthenticated,
  );

  if (isAuthenticated) {
    unawaited(repo.syncFromRemote());
  }

  ref.onDispose(repo.dispose);
  return repo;
});

/// Reactive stream provider for wishlisted product IDs.
/// Uses async* to yield local cached IDs first and then stream updates.
final savedProductIdsStreamProvider =
    StreamProvider<List<String>>((ref) async* {
  final wishlistRepo = ref.watch(shopWishlistRepositoryProvider);
  yield await wishlistRepo.getSavedProductIds();
  yield* wishlistRepo.watchSavedProductIds();
});

/// Central provider for external shopping launcher.
/// Uses `ExternalShopLauncher` which suppresses OS dispatch on demo items
/// and performs validated HTTPS handoff on real items.
final shopLauncherProvider = Provider<ShopLauncherContract>((ref) {
  return const ExternalShopLauncher();
});
