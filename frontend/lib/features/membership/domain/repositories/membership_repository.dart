import '../models/membership_plan.dart';
import '../../data/models/account_membership_dto.dart';

abstract class MembershipRepository {
  /// Returns published membership plans from backend catalog,
  /// falling back gracefully to baseline preview catalog if offline.
  Future<List<MembershipPlan>> getCatalogPlans({bool forceRefresh = false});

  /// Returns authenticated account membership and quota usage summary,
  /// falling back to standard Free tier baseline if unauthenticated or offline.
  Future<AccountMembershipDto> getAccountMembership();

  /// Returns account membership state distinguishing authoritative known, stale cache, and unknown error.
  Future<AccountMembershipState> getAccountMembershipState({String? accountId});

  /// Returns feature comparison matrix.
  Future<List<MatrixFeature>> getMatrixFeatures();

  /// Manages multi-tenant cache isolation and session epochs.
  void setActiveAccount(String? accountId);
  void clearAccountCache([String? accountId]);
}
