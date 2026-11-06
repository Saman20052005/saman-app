import 'package:equatable/equatable.dart';
import '../entities/shop_product.dart';

enum LauncherResultType {
  /// Demo / sample product: platform intent is intentionally suppressed; shows explanation to user.
  demo,

  /// Operating system accepted external launch request.
  dispatched,

  /// Launch request failed or encountered an exception.
  failed,
}

/// Typed outcome of attempting to open an external shopping URL.
class LauncherResult extends Equatable {
  final LauncherResultType type;
  final String? message;
  final String? targetUrl;

  const LauncherResult({
    required this.type,
    this.message,
    this.targetUrl,
  });

  factory LauncherResult.demo(String? url,
      [String message =
          'Sản phẩm minh họa: tính năng mở liên kết ngoài tạm tắt trong chế độ thử nghiệm.']) {
    return LauncherResult(
      type: LauncherResultType.demo,
      targetUrl: url,
      message: message,
    );
  }

  factory LauncherResult.dispatched(String url) {
    return LauncherResult(
      type: LauncherResultType.dispatched,
      targetUrl: url,
    );
  }

  factory LauncherResult.failed(String? url, String message) {
    return LauncherResult(
      type: LauncherResultType.failed,
      targetUrl: url,
      message: message,
    );
  }

  @override
  List<Object?> get props => [type, message, targetUrl];
}

/// Contract for dispatching external shopping links.
abstract interface class ShopLauncherContract {
  /// Attempts to launch the product's destination URL.
  Future<LauncherResult> launch(ShopProduct product);

  /// Checks if a given URL can be launched by the platform.
  Future<bool> canLaunch(String url);
}
