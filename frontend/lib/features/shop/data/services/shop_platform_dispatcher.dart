import 'package:url_launcher/url_launcher.dart';

/// Signature for url_launcher's `launchUrl`.
typedef LaunchUrlFunction = Future<bool> Function(
  Uri url, {
  LaunchMode mode,
  WebViewConfiguration webViewConfiguration,
  String? webOnlyWindowName,
});

/// Pluggable platform dispatcher isolating `url_launcher` plugin invocation
/// for testability without hardware/OS side effects.
abstract interface class ShopPlatformDispatcher {
  /// Dispatches the URI to the host OS with the specified [LaunchMode].
  Future<bool> dispatchUrl(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  });
}

/// Standard production implementation delegating directly to `package:url_launcher`.
class DefaultShopPlatformDispatcher implements ShopPlatformDispatcher {
  const DefaultShopPlatformDispatcher({LaunchUrlFunction? launchUrlFn})
      : _launchUrlFn = launchUrlFn ?? launchUrl;

  final LaunchUrlFunction _launchUrlFn;

  @override
  Future<bool> dispatchUrl(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) {
    return _launchUrlFn(uri, mode: mode);
  }
}

