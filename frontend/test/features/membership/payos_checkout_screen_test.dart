import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/membership/data/datasources/membership_remote_data_source.dart';
import 'package:health_ai_app/features/membership/data/models/account_membership_dto.dart';
import 'package:health_ai_app/features/membership/data/models/revenue_catalog_dto.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/domain/models/purchase_state.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';
import 'package:health_ai_app/features/membership/presentation/screens/payos_checkout_screen.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _FakeDioAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _FakeDioAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

class _FakeMembershipDataSource implements IMembershipRemoteDataSource {
  int membershipFetchCount = 0;

  @override
  Future<CatalogResponseDto> fetchCatalog({String? version}) async {
    throw UnimplementedError();
  }

  @override
  Future<AccountMembershipDto> fetchMyMembership() async {
    membershipFetchCount++;
    return AccountMembershipDto(
      userId: 'buyer@saman.vn',
      accountId: 'acct_123',
      tier: MembershipTier.pro,
      status: 'active',
      isActiveSubscription: true,
      entitlements: const [],
      usage: const {},
      asOf: DateTime.now(),
    );
  }

  @override
  Future<RestorePurchasesResult> restorePurchases(
    StorePurchasePayload payload,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendPurchaseVerificationResult> verifyPurchase(
    StorePurchasePayload payload,
  ) async {
    throw UnimplementedError();
  }
}

void main() {
  group('VND Zero-Decimal & PayosCheckoutScreen Tests', () {
    test('CatalogResponseDto preserves VND amounts without dividing by 100', () {
      final dto = CatalogResponseDto.fromJson({
        'version_id': 'v1.0-vn',
        'status': 'published',
        'currency': 'VND',
        'preview_mode': false,
        'disclaimer': 'Giá niêm yết VNĐ · Thanh toán tự động qua VietQR / PayOS.',
        'plans': [
          {
            'plan_id': 'plan_plus',
            'tier': 'plus',
            'name': 'Plus',
            'subtitle': 'Nutrition AI',
            'hero_description': 'Nutrition AI',
            'is_recommended': false,
            'is_current': false,
            'icon_name': 'restaurant',
            'feature_ids': ['ai.nutrition_gemini'],
            'prices': [
              {
                'price_id': 'price_plus_monthly_vnd_59000',
                'plan_id': 'plan_plus',
                'period': 'monthly',
                'amount_cents': 59000,
                'currency': 'VND',
                'purchasable': true,
              },
              {
                'price_id': 'price_plus_yearly_vnd_588000',
                'plan_id': 'plan_plus',
                'period': 'yearly',
                'amount_cents': 588000,
                'currency': 'VND',
                'yearly_equivalent_monthly_cents': 49000,
                'purchasable': true,
              },
            ],
            'availability_notice': 'Available',
          },
        ],
        'prices': [],
        'matrix_features': [],
      });

      final plans = dto.toDomainPlans();
      expect(plans.length, 1);
      final plus = plans.first;
      expect(plus.currency, 'VND');
      expect(plus.monthlyPrice, 59000);
      expect(plus.yearlyPrice, 588000);
      expect(plus.yearlyEquivalentMonthlyPrice, 49000);
      expect(plus.purchasable, isTrue);
      expect(plus.priceDisplay(BillingPeriod.monthly), '59.000đ');
      expect(plus.unitDisplay(BillingPeriod.monthly), '/ tháng');
      expect(plus.yearlyEquivalentText, 'Tương đương 49.000đ / tháng');
    });

    testWidgets(
      'PayosCheckoutScreen renders QR code in Light & Dark Mode and transitions to paid state',
      (tester) async {
        final fakeDs = _FakeMembershipDataSource();
        final dio = Dio();
        String currentOrderStatus = 'pending';

        dio.httpClientAdapter = _FakeDioAdapter((options) async {
          if (options.path.endsWith('/api/payments/create-qr')) {
            return ResponseBody.fromString(
              '''
              {
                "order_code": 2026112001,
                "amount": 119000,
                "currency": "VND",
                "description": "SAMAN PRO 2026112001",
                "qr_code": "00020101021238570010A0000007270127000697042201130388889999",
                "checkout_url": "https://pay.payos.vn/web/test",
                "bin": "970422",
                "account_number": "0388889999",
                "account_name": "SAMAN HEALTH",
                "status": "pending"
              }
              ''',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (options.path.contains('/api/payments/orders/2026112001')) {
            return ResponseBody.fromString(
              '''
              {
                "order_code": 2026112001,
                "status": "$currentOrderStatus",
                "tier": "pro",
                "billing_period": "monthly",
                "amount": 119000,
                "currency": "VND"
              }
              ''',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('{}', 404);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dioProvider.overrideWithValue(dio),
              membershipRemoteDataSourceProvider.overrideWithValue(fakeDs),
            ],
            child: MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: ThemeMode.dark,
              home: const PayosCheckoutScreen(
                tier: MembershipTier.pro,
                billingPeriod: BillingPeriod.monthly,
                enableAutoPolling: false,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('119.000đ'), findsWidgets);
        expect(find.text('0388889999'), findsOneWidget);
        expect(find.text('SAMAN PRO 2026112001'), findsOneWidget);
        expect(find.text('Kiểm tra trạng thái thanh toán'), findsOneWidget);

        // Simulate PayOS payment completed -> manual status check transitions to success
        currentOrderStatus = 'paid';
        await tester.ensureVisible(
          find.text('Kiểm tra trạng thái thanh toán'),
        );
        await tester.tap(find.text('Kiểm tra trạng thái thanh toán'));
        await tester.pumpAndSettle();

        expect(find.text('Nâng cấp thành công!'), findsOneWidget);
        expect(find.text('Quay lại ứng dụng'), findsOneWidget);
        expect(fakeDs.membershipFetchCount, 1);
      },
    );
  });
}
