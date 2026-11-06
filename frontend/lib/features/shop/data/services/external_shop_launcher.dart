import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/shop_product.dart';
import '../../domain/services/shop_launcher_contract.dart';
import '../../domain/services/shop_url_policy.dart';
import 'shop_platform_dispatcher.dart';

/// Real production implementation of `ShopLauncherContract`.
///
/// Features:
/// - Enforces strict HTTPS allowlist policy via `ShopUrlPolicy`.
/// - Protects M1 demo products: suppresses OS handoff and returns typed demo result.
/// - Uses `LaunchMode.externalApplication` to defer browsing/shopping to user's installed browser or app.
/// - Supports full test isolation via injectable `ShopPlatformDispatcher`.
class ExternalShopLauncher implements ShopLauncherContract {
  const ExternalShopLauncher({
    ShopUrlPolicy? urlPolicy,
    ShopPlatformDispatcher? platformDispatcher,
  })  : _urlPolicy = urlPolicy ?? const ShopUrlPolicy(),
        _platformDispatcher =
            platformDispatcher ?? const DefaultShopPlatformDispatcher();

  final ShopUrlPolicy _urlPolicy;
  final ShopPlatformDispatcher _platformDispatcher;

  @override
  Future<LauncherResult> launch(ShopProduct product) async {
    // 1. Demo Mode: Suppress OS dispatch unconditionally for demo products
    if (product.isDemo) {
      return LauncherResult.demo(
        product.shopeeUrl,
        'Sản phẩm minh họa, chưa có liên kết mua thực tế.',
      );
    }

    // 2. Availability Guard: Inactive / discontinued items cannot be dispatched
    if (product.availability != ProductAvailability.available) {
      return LauncherResult.failed(
        product.shopeeUrl,
        'Sản phẩm hiện không khả dụng để mua sắm',
      );
    }

    // 3. Missing URL Guard
    final rawUrl = product.shopeeUrl;
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return LauncherResult.failed(
        null,
        'Sản phẩm chưa có liên kết mua sắm Shopee',
      );
    }

    // 4. URL Policy & Host Allowlist Validation
    final validation = _urlPolicy.validate(rawUrl);
    if (!validation.isValid || validation.uri == null) {
      return LauncherResult.failed(
        rawUrl,
        validation.errorMessage ?? 'Liên kết sản phẩm không hợp lệ',
      );
    }

    // 5. External Application Dispatch
    try {
      final success = await _platformDispatcher.dispatchUrl(
        validation.uri!,
        mode: LaunchMode.externalApplication,
      );

      if (success) {
        return LauncherResult.dispatched(rawUrl);
      } else {
        return LauncherResult.failed(
          rawUrl,
          'Thiết bị không thể mở liên kết mua sắm',
        );
      }
    } catch (_) {
      // Safe generic failure — do not leak internal stack or raw exception
      return LauncherResult.failed(
        rawUrl,
        'Lỗi kết nối khi mở ứng dụng mua sắm',
      );
    }
  }

  @override
  Future<bool> canLaunch(String url) async {
    final validation = _urlPolicy.validate(url);
    return validation.isValid;
  }
}

