import '../../domain/models/purchase_state.dart';
import '../../domain/repositories/payment_repository.dart';
import '../datasources/membership_remote_data_source.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  final StorePaymentClientAdapter _storeAdapter;
  final IMembershipRemoteDataSource _remoteDataSource;

  PaymentRepositoryImpl({
    StorePaymentClientAdapter? storeAdapter,
    IMembershipRemoteDataSource? remoteDataSource,
  })  : _storeAdapter =
            storeAdapter ?? const UnconfiguredStorePaymentClientAdapter(),
        _remoteDataSource = remoteDataSource ?? MembershipRemoteDataSourceImpl();

  @override
  bool get isPaymentConfigured => _storeAdapter.isConfigured;

  @override
  Future<StoreClientOutcome> startStorePurchase(PurchaseIntent intent) async {
    if (!intent.plan.purchasable || !_storeAdapter.isConfigured) {
      return StoreClientOutcome.unavailable(
        'Selected plan or payment provider is in preview mode and not yet purchasable.',
      );
    }
    return _storeAdapter.initiateStorePurchase(intent);
  }

  @override
  Future<BackendPurchaseVerificationResult> verifyPurchaseWithBackend(
    StorePurchasePayload payload,
  ) {
    return _remoteDataSource.verifyPurchase(payload);
  }

  @override
  Future<StoreClientOutcome> startStoreRestore() async {
    if (!_storeAdapter.isConfigured) {
      return StoreClientOutcome.unavailable(
        'Payment provider is not yet configured. Live restore is unavailable.',
      );
    }
    return _storeAdapter.queryPastPurchases();
  }

  @override
  Future<RestorePurchasesResult> restorePurchasesWithBackend(
    StorePurchasePayload payload,
  ) {
    return _remoteDataSource.restorePurchases(payload);
  }
}
