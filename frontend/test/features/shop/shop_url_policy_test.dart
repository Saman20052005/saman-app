import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/shop/domain/services/shop_url_policy.dart';

void main() {
  group('ShopUrlPolicy — Strict Security & URL Validation', () {
    late ShopUrlPolicy policy;

    setUp(() {
      policy = const ShopUrlPolicy();
    });

    test('accepts valid HTTPS URL on approved host (shopee.vn)', () {
      final result = policy.validate('https://shopee.vn/product/matte-shaker-750ml');
      expect(result.isValid, isTrue);
      expect(result.uri, isNotNull);
      expect(result.uri?.host, 'shopee.vn');
      expect(result.uri?.path, '/product/matte-shaker-750ml');
      expect(result.error, isNull);
    });

    test('normalizes uppercase hostname to lowercase and accepts', () {
      final result = policy.validate('HTTPS://SHOPEE.VN/item-123');
      expect(result.isValid, isTrue);
      expect(result.uri?.host.toLowerCase(), 'shopee.vn');
    });

    test('preserves query parameters and affiliate/attribution tracking unchanged', () {
      const url =
          'https://shopee.vn/product/matte-shaker?sp_atk=abc-123&utm_source=saman&af_id=987';
      final result = policy.validate(url);
      expect(result.isValid, isTrue);
      expect(result.uri.toString(), url);
      expect(result.uri?.queryParameters['sp_atk'], 'abc-123');
      expect(result.uri?.queryParameters['utm_source'], 'saman');
      expect(result.uri?.queryParameters['af_id'], '987');
    });

    test('preserves URL fragment/hash anchor without modification', () {
      const url = 'https://shopee.vn/product/123#specifications';
      final result = policy.validate(url);
      expect(result.isValid, isTrue);
      expect(result.uri.toString(), url);
      expect(result.uri?.fragment, 'specifications');
    });

    test('rejects null, empty, or whitespace-only strings', () {
      final nullResult = policy.validate(null);
      expect(nullResult.isValid, isFalse);
      expect(nullResult.error, ShopUrlValidationError.empty);

      final emptyResult = policy.validate('');
      expect(emptyResult.isValid, isFalse);
      expect(emptyResult.error, ShopUrlValidationError.empty);

      final spacesResult = policy.validate('    ');
      expect(spacesResult.isValid, isFalse);
      expect(spacesResult.error, ShopUrlValidationError.empty);
    });

    test('rejects malformed URLs without valid scheme or authority', () {
      final malformed1 = policy.validate('not_a_valid_url');
      expect(malformed1.isValid, isFalse);
      expect(malformed1.error, ShopUrlValidationError.malformed);

      final malformed2 = policy.validate('://broken-uri');
      expect(malformed2.isValid, isFalse);
      expect(malformed2.error, ShopUrlValidationError.malformed);
    });

    test('rejects non-HTTPS schemes (HTTP, custom schemes, scripts)', () {
      final http = policy.validate('http://shopee.vn/item');
      expect(http.isValid, isFalse);
      expect(http.error, ShopUrlValidationError.nonHttpsScheme);

      final deepLink = policy.validate('shopee://product/123');
      expect(deepLink.isValid, isFalse);
      expect(deepLink.error, ShopUrlValidationError.nonHttpsScheme);

      final script = policy.validate('javascript:alert(1)');
      expect(script.isValid, isFalse);
      expect(script.error, ShopUrlValidationError.nonHttpsScheme);

      final ftp = policy.validate('ftp://shopee.vn/item');
      expect(ftp.isValid, isFalse);
      expect(ftp.error, ShopUrlValidationError.nonHttpsScheme);
    });

    test('rejects userinfo injection (e.g. https://shopee.vn@evil.example)', () {
      // Browsers and parsers treat userinfo before @ as credential, authority is evil.example
      final spoof = policy.validate('https://shopee.vn@evil.example/item');
      expect(spoof.isValid, isFalse);
      expect(
        spoof.error == ShopUrlValidationError.userInfoDisallowed ||
            spoof.error == ShopUrlValidationError.unapprovedHost,
        isTrue,
      );

      final userPass = policy.validate('https://admin:pass@shopee.vn/item');
      expect(userPass.isValid, isFalse);
      expect(userPass.error, ShopUrlValidationError.userInfoDisallowed);
    });

    test('rejects non-standard ports (e.g. :8080, :80)', () {
      final port8080 = policy.validate('https://shopee.vn:8080/item');
      expect(port8080.isValid, isFalse);
      expect(port8080.error, ShopUrlValidationError.invalidPort);

      final port80 = policy.validate('https://shopee.vn:80/item');
      expect(port80.isValid, isFalse);
      expect(port80.error, ShopUrlValidationError.invalidPort);

      // Port 443 is explicitly valid standard HTTPS
      final port443 = policy.validate('https://shopee.vn:443/item');
      expect(port443.isValid, isTrue);
    });

    test('rejects host spoofing, trick domains, and look-alikes', () {
      // shopee.vn.evil.example
      final subEvil = policy.validate('https://shopee.vn.evil.example/item');
      expect(subEvil.isValid, isFalse);
      expect(subEvil.error, ShopUrlValidationError.unapprovedHost);

      // evilshopee.vn
      final typoDomain = policy.validate('https://evilshopee.vn/item');
      expect(typoDomain.isValid, isFalse);
      expect(typoDomain.error, ShopUrlValidationError.unapprovedHost);

      // shopeevn.com
      final comDomain = policy.validate('https://shopeevn.com/item');
      expect(comDomain.isValid, isFalse);
      expect(comDomain.error, ShopUrlValidationError.unapprovedHost);
    });

    test('rejects unverified subdomains by exact match rule', () {
      final apiSub = policy.validate('https://api.shopee.vn/item');
      expect(apiSub.isValid, isFalse);
      expect(apiSub.error, ShopUrlValidationError.unapprovedHost);

      final mallSub = policy.validate('https://mall.shopee.vn/item');
      expect(mallSub.isValid, isFalse);
      expect(mallSub.error, ShopUrlValidationError.unapprovedHost);
    });

    test('rejects unconfigured short links and redirects', () {
      final shpEe = policy.validate('https://shp.ee/abc123xyz');
      expect(shpEe.isValid, isFalse);
      expect(shpEe.error, ShopUrlValidationError.unapprovedHost);

      final vnShpEe = policy.validate('https://vn.shp.ee/test-redirect');
      expect(vnShpEe.isValid, isFalse);
      expect(vnShpEe.error, ShopUrlValidationError.unapprovedHost);
    });

    test('supports configured custom allowlist for isolated test fixtures', () {
      const customPolicy = ShopUrlPolicy(
        approvedHosts: {'partner.saman.vn', 'shopee.vn'},
      );

      final partner = customPolicy.validate('https://partner.saman.vn/catalog/1');
      expect(partner.isValid, isTrue);
      expect(partner.uri?.host, 'partner.saman.vn');

      final shopee = customPolicy.validate('https://shopee.vn/item');
      expect(shopee.isValid, isTrue);

      final unapproved = customPolicy.validate('https://other.vn/item');
      expect(unapproved.isValid, isFalse);
      expect(unapproved.error, ShopUrlValidationError.unapprovedHost);
    });
  });
}

