import '../../domain/entities/shop_product.dart';
import '../../domain/services/shop_launcher_contract.dart';

enum FakeLauncherScenario {
  normal,
  forceFail,
}

/// Fake implementation of `ShopLauncherContract` for M1 testing and development.
/// Suppresses actual OS launch requests and returns typed simulation results.
class FakeShopLauncher implements ShopLauncherContract {
  FakeLauncherScenario scenario;
  String failureReason;

  FakeShopLauncher({
    this.scenario = FakeLauncherScenario.normal,
    this.failureReason = 'Không thể kết nối đến ứng dụng mua sắm trên thiết bị',
  });

  @override
  Future<LauncherResult> launch(ShopProduct product) async {
    if (scenario == FakeLauncherScenario.forceFail) {
      return LauncherResult.failed(product.shopeeUrl, failureReason);
    }

    if (product.isDemo) {
      return LauncherResult.demo(product.shopeeUrl);
    }

    if (!product.hasShopeeUrl) {
      return LauncherResult.failed(
          null, 'Sản phẩm chưa có liên kết mua sắm Shopee');
    }

    return LauncherResult.dispatched(product.shopeeUrl!);
  }

  @override
  Future<bool> canLaunch(String url) async {
    if (scenario == FakeLauncherScenario.forceFail) return false;
    return url.trim().isNotEmpty;
  }
}
