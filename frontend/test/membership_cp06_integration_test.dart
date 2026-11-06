import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/membership/data/models/account_membership_dto.dart';
import 'package:health_ai_app/features/membership/data/models/revenue_catalog_dto.dart';
import 'package:health_ai_app/features/membership/data/repositories/membership_repository_impl.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';
import 'package:health_ai_app/services/nutrition_service.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

void main() {
  group('CP-06 Revenue Catalog & Account DTO Tests', () {
    test('CatalogResponseDto parses backend JSON and maps to Domain MembershipPlan', () {
      final mockJson = {
        'version_id': 'v1.0-preview',
        'status': 'published',
        'currency': 'USD',
        'preview_mode': true,
        'disclaimer': 'Demo pricing · Subject to change. Not purchasable.',
        'plans': [
          {
            'plan_id': 'plan_free',
            'tier': 'free',
            'name': 'Free',
            'subtitle': 'Core essentials',
            'hero_description': 'Everyday tracking.',
            'is_recommended': false,
            'is_current': true,
            'icon_name': 'check_circle_outline',
            'feature_ids': ['core.nutrition_logging'],
            'prices': [
              {
                'price_id': 'price_free_monthly',
                'plan_id': 'plan_free',
                'period': 'monthly',
                'amount_cents': 0,
                'currency': 'USD',
                'purchasable': false,
              }
            ],
            'availability_notice': 'Included with free account.',
          },
          {
            'plan_id': 'plan_plus',
            'tier': 'plus',
            'name': 'Plus',
            'subtitle': 'Nutrition AI',
            'hero_description': 'Gemini photo analysis.',
            'is_recommended': false,
            'is_current': false,
            'icon_name': 'restaurant',
            'feature_ids': ['ai.nutrition_gemini'],
            'prices': [
              {
                'price_id': 'price_plus_monthly_usd_1000',
                'plan_id': 'plan_plus',
                'period': 'monthly',
                'amount_cents': 1000,
                'currency': 'USD',
                'purchasable': false,
              },
              {
                'price_id': 'price_plus_yearly_usd_6000',
                'plan_id': 'plan_plus',
                'period': 'yearly',
                'amount_cents': 6000,
                'currency': 'USD',
                'yearly_equivalent_monthly_cents': 500,
                'purchasable': false,
              }
            ],
            'availability_notice': 'Plus is not available yet.',
          }
        ],
        'prices': [],
        'matrix_features': [
          {
            'id': 'gemini_food_analysis',
            'title': 'Gemini food analysis',
            'group': 'NUTRITION AI',
            'status_map': {
              'free': 'not_included',
              'plus': 'planned',
              'pro': 'planned',
              'ultra': 'planned',
            }
          }
        ],
      };

      final dto = CatalogResponseDto.fromJson(mockJson);
      expect(dto.versionId, 'v1.0-preview');
      expect(dto.previewMode, isTrue);
      expect(dto.plans.length, 2);

      final domainPlans = dto.toDomainPlans();
      expect(domainPlans.length, 2);

      final plusPlan = domainPlans.firstWhere((p) => p.tier == MembershipTier.plus);
      expect(plusPlan.name, 'Plus');
      expect(plusPlan.monthlyPrice, 10); // $10 from 1000 cents
      expect(plusPlan.yearlyPrice, 60);  // $60 from 6000 cents
      expect(plusPlan.yearlyEquivalentMonthlyPrice, 5); // $5 from 500 cents
      expect(plusPlan.purchasable, isFalse); // Safety guarantee
    });

    test('AccountMembershipDto parses authenticated backend /membership/me response', () {
      final mockJson = {
        'user_id': 'test@saman.app',
        'tier': 'free',
        'status': 'none',
        'is_active_subscription': false,
        'current_period_end': null,
        'entitlements': [],
        'usage': {
          'ai.nutrition_gemini': {
            'benefit_id': 'ai.nutrition_gemini',
            'consumed_units': 5,
            'reserved_units': 1,
            'remaining_units': 24,
            'limit_units': 30,
            'period_key': 'monthly:202610',
            'reset_at': '2026-11-01T00:00:00Z',
          }
        },
        'as_of': '2026-10-29T11:00:00Z',
      };

      final dto = AccountMembershipDto.fromJson(mockJson);
      expect(dto.userId, 'test@saman.app');
      expect(dto.tier, MembershipTier.free);
      expect(dto.isActiveSubscription, isFalse);

      final geminiUsage = dto.nutritionGeminiUsage;
      expect(geminiUsage, isNotNull);
      expect(geminiUsage!.consumedUnits, 5);
      expect(geminiUsage.remainingUnits, 24);
      expect(geminiUsage.limitUnits, 30);
    });

    test('AccountMembershipDto.defaultFree() returns safe unmetered baseline Free', () {
      final defaultFree = AccountMembershipDto.defaultFree();
      expect(defaultFree.tier, MembershipTier.free);
      expect(defaultFree.status, 'none');
      expect(defaultFree.isActiveSubscription, isFalse);
      expect(defaultFree.nutritionGeminiUsage?.remainingUnits, 30);
    });
  });

  group('CP-06 Repository Offline Fallback & Caching', () {
    test('MembershipRepositoryImpl falls back to static catalog when offline', () async {
      final repo = MembershipRepositoryImpl();
      final plans = await repo.getCatalogPlans();
      expect(plans.length, 4);
      expect(plans.first.tier, MembershipTier.free);
    });

    test('MembershipRepositoryImpl falls back to defaultFree when offline', () async {
      final repo = MembershipRepositoryImpl();
      final account = await repo.getAccountMembership();
      expect(account.tier, MembershipTier.free);
      expect(account.status, 'none');
    });
  });

  group('CP-06 Nutrition Paywall & Error Mapping Tests', () {
    test('foodAnalysisErrorMessage handles EntitlementRequiredException', () {
      const err = EntitlementRequiredException('Upgrade to Plus for advanced photo analysis.');
      expect(foodAnalysisErrorMessage(err), 'Upgrade to Plus for advanced photo analysis.');
    });

    test('foodAnalysisErrorMessage handles QuotaExhaustedException', () {
      const err = QuotaExhaustedException('Monthly limit reached.');
      expect(foodAnalysisErrorMessage(err), 'Monthly limit reached.');
    });

    test('foodAnalysisErrorMessage maps Dio 403 entitlement_required', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/api/food/analyze'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/food/analyze'),
          statusCode: 403,
          data: {
            'detail': 'Advanced nutrition analysis requires Plus membership or higher.',
            'error_code': 'entitlement_required',
          },
        ),
      );
      expect(
        foodAnalysisErrorMessage(dioErr),
        'Advanced nutrition analysis requires Plus membership or higher.',
      );
    });

    test('foodAnalysisErrorMessage maps Dio 429 quota_exhausted', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/api/food/analyze'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/food/analyze'),
          statusCode: 429,
          data: {
            'detail': 'Monthly quota exhausted for advanced nutrition analysis (limit: 30).',
            'error_code': 'quota_exhausted',
          },
        ),
      );
      expect(
        foodAnalysisErrorMessage(dioErr),
        'Monthly quota exhausted for advanced nutrition analysis (limit: 30).',
      );
    });

    test('foodAnalysisErrorMessage maps Dio 409 operation conflict', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/api/food/analyze'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/food/analyze'),
          statusCode: 409,
          data: {
            'detail': 'An operation with this idempotency key is already in progress.',
            'error_code': 'operation_in_progress',
          },
        ),
      );
      expect(
        foodAnalysisErrorMessage(dioErr),
        'An operation with this idempotency key is already in progress.',
      );
    });

    test('foodAnalysisErrorMessage maps Dio 504 provider timeout', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/api/food/analyze'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/food/analyze'),
          statusCode: 504,
          data: {
            'detail': 'AI food analysis timed out. Please try again.',
            'error_code': 'provider_timeout',
          },
        ),
      );
      expect(
        foodAnalysisErrorMessage(dioErr),
        'AI food analysis timed out. Please try again.',
      );
    });
  });

  group('CP-06 Tenant Isolation on Logout', () {
    test('accountMembershipProvider resets to defaultFree on logout', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initial = container.read(accountMembershipProvider);
      expect(initial.tier, MembershipTier.free);

      // Trigger logout
      container.read(authLoggingOutProvider.notifier).state = true;
      final afterLogout = container.read(accountMembershipProvider);
      expect(afterLogout.tier, MembershipTier.free);
      expect(afterLogout.status, 'none');
    });
  });
}

