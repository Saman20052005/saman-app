import 'package:equatable/equatable.dart';

/// Error categories for shopping URL validation.
enum ShopUrlValidationError {
  empty,
  malformed,
  nonHttpsScheme,
  userInfoDisallowed,
  invalidPort,
  unapprovedHost,
}

/// Typed validation outcome for external product destination URLs.
class ShopUrlValidationResult extends Equatable {
  const ShopUrlValidationResult.valid(this.uri)
      : isValid = true,
        error = null,
        errorMessage = null;

  const ShopUrlValidationResult.invalid(this.error, this.errorMessage)
      : isValid = false,
        uri = null;

  final bool isValid;
  final Uri? uri;
  final ShopUrlValidationError? error;
  final String? errorMessage;

  @override
  List<Object?> get props => [isValid, uri, error, errorMessage];
}

/// Strict URL security policy enforcing safe HTTPS external handoffs.
///
/// Rules:
/// 1. Only HTTPS scheme is permitted.
/// 2. Hostname must strictly match an approved allowlist (no loose `contains`, no unverified subdomains).
/// 3. Userinfo (e.g. `user:pass@host`) is rejected to prevent URL spoofing.
/// 4. Non-standard ports (e.g. 8080) are rejected.
/// 5. Valid query parameters, fragments, and attribution markers are strictly preserved.
/// 6. Short links and redirects are rejected unless explicitly allowlisted with verified justification.
class ShopUrlPolicy {
  /// Default verified allowlist of hosts.
  ///
  /// Verified Sources & Rationale:
  /// - `shopee.vn`: Primary official verified e-commerce marketplace domain for Shopee Vietnam
  ///   (PRD §1 & §2: Curated boutique handoff to Shopee).
  ///
  /// Note on Short Links / Redirects:
  /// Domains such as `shp.ee` or `vn.shp.ee` are intentionally excluded from the default allowlist
  /// because unverified redirects present phishing and intent-hijacking vectors until an authenticated
  /// backend canonical resolution contract is in place.
  static const Set<String> defaultApprovedHosts = {'shopee.vn'};

  const ShopUrlPolicy({Set<String>? approvedHosts})
      : _approvedHosts = approvedHosts ?? defaultApprovedHosts;

  final Set<String> _approvedHosts;

  Set<String> get approvedHosts => Set.unmodifiable(_approvedHosts);

  /// Validates [urlString] against strict HTTPS allowlist criteria without modifying
  /// legitimate query parameters or fragments.
  ShopUrlValidationResult validate(String? urlString) {
    if (urlString == null || urlString.trim().isEmpty) {
      return const ShopUrlValidationResult.invalid(
        ShopUrlValidationError.empty,
        'Đường dẫn liên kết không được để trống',
      );
    }

    final trimmed = urlString.trim();
    final uri = Uri.tryParse(trimmed);

    if (uri == null || !uri.hasScheme) {
      return const ShopUrlValidationResult.invalid(
        ShopUrlValidationError.malformed,
        'Cấu trúc liên kết không hợp lệ',
      );
    }

    // Rule 1: Strictly HTTPS scheme
    if (uri.scheme.toLowerCase() != 'https') {
      return const ShopUrlValidationResult.invalid(
        ShopUrlValidationError.nonHttpsScheme,
        'Chỉ chấp nhận liên kết bảo mật HTTPS',
      );
    }

    if (uri.host.isEmpty) {
      return const ShopUrlValidationResult.invalid(
        ShopUrlValidationError.malformed,
        'Cấu trúc liên kết không hợp lệ',
      );
    }

    // Rule 2: Reject userinfo (e.g. https://shopee.vn@evil.example)
    if (uri.userInfo.isNotEmpty) {
      return const ShopUrlValidationResult.invalid(
        ShopUrlValidationError.userInfoDisallowed,
        'Liên kết chứa thông tin người dùng không được phép',
      );
    }

    // Rule 3: Reject non-standard ports (standard HTTPS port is 443 or default/null/0)
    if (uri.hasPort && uri.port != 443 && uri.port != 0) {
      return const ShopUrlValidationResult.invalid(
        ShopUrlValidationError.invalidPort,
        'Cổng kết nối không được phép',
      );
    }

    // Rule 4: Host comparison must be exact and case-insensitive against approved allowlist.
    // Subdomains and spoofed look-alikes are rejected.
    final host = uri.host.toLowerCase();
    if (!_approvedHosts.contains(host)) {
      return const ShopUrlValidationResult.invalid(
        ShopUrlValidationError.unapprovedHost,
        'Tên miền đích chưa được phê duyệt trong danh mục tin cậy',
      );
    }

    // Rule 5: Preservation: return original parsed Uri with query and fragment intact
    return ShopUrlValidationResult.valid(uri);
  }
}
