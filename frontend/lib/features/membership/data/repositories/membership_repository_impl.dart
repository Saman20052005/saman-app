import 'package:flutter/foundation.dart';
import '../../domain/models/membership_plan.dart';
import '../../domain/repositories/membership_repository.dart';
import '../datasources/membership_remote_data_source.dart';
import '../models/account_membership_dto.dart';

class MembershipRepositoryImpl implements MembershipRepository {
  final IMembershipRemoteDataSource _remoteDataSource;

  List<MembershipPlan>? _cachedPlans;
  List<MatrixFeature>? _cachedMatrix;
  AccountMembershipDto? _cachedMembership;

  // Account cache partitioned by userId: userId -> (data, fetchedAt)
  final Map<String, (AccountMembershipDto, DateTime)> _accountCache = {};
  int _sessionEpoch = 0;
  String? _activeAccountId;

  MembershipRepositoryImpl({
    IMembershipRemoteDataSource? remoteDataSource,
  }) : _remoteDataSource =
            remoteDataSource ?? MembershipRemoteDataSourceImpl();

  @override
  Future<List<MembershipPlan>> getCatalogPlans(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPlans != null && _cachedPlans!.isNotEmpty) {
      return _cachedPlans!;
    }

    try {
      final catalogDto = await _remoteDataSource.fetchCatalog();
      final domainPlans = catalogDto.toDomainPlans();
      if (domainPlans.isNotEmpty) {
        _cachedPlans = domainPlans;
        if (catalogDto.matrixFeatures.isNotEmpty) {
          _cachedMatrix =
              catalogDto.matrixFeatures.map((m) => m.toDomain()).toList();
        }
        return domainPlans;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[MembershipRepository] Failed to fetch remote catalog, falling back to static preview: $e');
      }
    }

    // Graceful offline fallback
    return _cachedPlans ?? MembershipCatalog.plans;
  }

  @override
  void setActiveAccount(String? accountId) {
    if (_activeAccountId != accountId) {
      _activeAccountId = accountId;
      _sessionEpoch++;
    }
  }

  @override
  void clearAccountCache([String? accountId]) {
    if (accountId != null) {
      _accountCache.remove(accountId);
    } else {
      _accountCache.clear();
      _cachedMembership = null;
      _activeAccountId = null;
      _sessionEpoch++;
    }
  }

  (AccountMembershipDto, DateTime)? getCachedMembership(String accountId) {
    return _accountCache[accountId];
  }

  @override
  Future<AccountMembershipState> getAccountMembershipState(
      {String? accountId}) async {
    if (accountId != null && accountId != _activeAccountId) {
      _activeAccountId = accountId;
      _sessionEpoch++;
    }
    final targetAccount = accountId ?? _activeAccountId;
    final requestEpoch = _sessionEpoch;

    try {
      final membership = await _remoteDataSource.fetchMyMembership();
      // Guard against race conditions and responses from obsolete session epochs
      if (_sessionEpoch != requestEpoch) {
        if (kDebugMode) {
          debugPrint(
              '[MembershipRepository] Discarding response from obsolete session epoch $requestEpoch (current: $_sessionEpoch)');
        }
        if (targetAccount != null && _accountCache.containsKey(targetAccount)) {
          final cached = _accountCache[targetAccount]!;
          return AccountMembershipState.stale(cached.$1, cached.$2);
        }
        return AccountMembershipState.unknownError(
            'Session changed while fetching membership',
            accountId: targetAccount);
      }

      // Guard against cross-account response contamination
      if (targetAccount != null &&
          membership.userId.isNotEmpty &&
          membership.userId != targetAccount) {
        if (kDebugMode) {
          debugPrint(
              '[MembershipRepository] Rejecting mismatched account payload (${membership.userId} != $targetAccount)');
        }
        return AccountMembershipState.unknownError(
            'Account identity mismatch in membership response',
            accountId: targetAccount);
      }

      final effectiveUser = membership.userId.isNotEmpty
          ? membership.userId
          : (targetAccount ?? 'me');
      final now = DateTime.now();
      _accountCache[effectiveUser] = (membership, now);
      _cachedMembership = membership;
      return AccountMembershipState.known(membership, fetchedAt: now);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[MembershipRepository] Failed to fetch account membership: $e');
      }

      // Check if we have cached data for target account
      if (targetAccount != null && _accountCache.containsKey(targetAccount)) {
        final cached = _accountCache[targetAccount]!;
        return AccountMembershipState.stale(cached.$1, cached.$2,
            errorMessage: e.toString());
      }

      if (_cachedMembership != null &&
          (targetAccount == null ||
              _cachedMembership!.userId == targetAccount)) {
        return AccountMembershipState.stale(_cachedMembership!, DateTime.now(),
            errorMessage: e.toString());
      }

      // DO NOT fabricate Free tier on failure! Return explicit unknown state.
      return AccountMembershipState.unknownError(e.toString(),
          accountId: targetAccount);
    }
  }

  @override
  Future<AccountMembershipDto> getAccountMembership() async {
    final state = await getAccountMembershipState();
    if (state.hasValidData && state.data != null) {
      return state.data!;
    }
    return state.data ?? AccountMembershipDto.defaultFree();
  }

  @override
  Future<List<MatrixFeature>> getMatrixFeatures() async {
    if (_cachedMatrix != null && _cachedMatrix!.isNotEmpty) {
      return _cachedMatrix!;
    }

    try {
      final catalogDto = await _remoteDataSource.fetchCatalog();
      if (catalogDto.matrixFeatures.isNotEmpty) {
        final matrix =
            catalogDto.matrixFeatures.map((m) => m.toDomain()).toList();
        _cachedMatrix = matrix;
        return matrix;
      }
    } catch (_) {}

    return MembershipCatalog.matrixFeatures;
  }

  void clearCache() {
    _cachedPlans = null;
    _cachedMatrix = null;
    _cachedMembership = null;
    _accountCache.clear();
    _activeAccountId = null;
    _sessionEpoch++;
  }
}
