import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../config/api_config.dart';
import '../../../../services/api_client.dart';
import '../models/revenue_catalog_dto.dart';
import '../models/account_membership_dto.dart';
import '../../domain/models/purchase_state.dart';

abstract class IMembershipRemoteDataSource {
  Future<CatalogResponseDto> fetchCatalog({String? version});
  Future<AccountMembershipDto> fetchMyMembership();
  Future<BackendPurchaseVerificationResult> verifyPurchase(
    StorePurchasePayload payload,
  );
  Future<RestorePurchasesResult> restorePurchases(
    StorePurchasePayload payload,
  );
}

class MembershipRemoteDataSourceImpl implements IMembershipRemoteDataSource {
  final Dio _dio;

  MembershipRemoteDataSourceImpl({Dio? dio}) : _dio = dio ?? ApiClient.dio;

  @override
  Future<CatalogResponseDto> fetchCatalog({String? version}) async {
    const endpoint = '${ApiConfig.baseUrl}/api/revenue/catalog';
    final queryParams = <String, dynamic>{
      if (version != null && version.isNotEmpty) 'version': version,
    };

    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        return CatalogResponseDto.fromJson(Map<String, dynamic>.from(data as Map));
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MembershipRemoteDataSource] fetchCatalog error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<AccountMembershipDto> fetchMyMembership() async {
    const endpoint = '${ApiConfig.baseUrl}/api/revenue/membership/me';

    try {
      final response = await _dio.get(endpoint);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        return AccountMembershipDto.fromJson(Map<String, dynamic>.from(data as Map));
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MembershipRemoteDataSource] fetchMyMembership error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<BackendPurchaseVerificationResult> verifyPurchase(
    StorePurchasePayload payload,
  ) async {
    const endpoint = '${ApiConfig.baseUrl}/api/revenue/purchases/verify';

    try {
      final response = await _dio.post(
        endpoint,
        data: payload.toVerificationJson(),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        return BackendPurchaseVerificationResult.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MembershipRemoteDataSource] verifyPurchase error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<RestorePurchasesResult> restorePurchases(
    StorePurchasePayload payload,
  ) async {
    const endpoint = '${ApiConfig.baseUrl}/api/revenue/purchases/restore';

    try {
      final response = await _dio.post(
        endpoint,
        data: payload.toVerificationJson(),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        return RestorePurchasesResult.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MembershipRemoteDataSource] restorePurchases error: $e');
      }
      rethrow;
    }
  }
}
