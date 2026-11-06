import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/failures/shop_failure.dart';
import '../../domain/repositories/shop_wishlist_repository.dart';

/// SharedPreferences implementation of `ShopWishlistRepository` with write serialization.
class SharedPreferencesShopWishlistRepository
    implements ShopWishlistRepository {
  static const String storageKey = 'saman_shop_wishlist_ids_v1';

  final SharedPreferences _prefs;
  final _controller = StreamController<List<String>>.broadcast();

  /// Lock chain to serialize concurrent read-modify-write operations FIFO.
  Future<void> _writeQueue = Future.value();

  SharedPreferencesShopWishlistRepository(this._prefs);

  @override
  Future<List<String>> getSavedProductIds() async {
    try {
      if (!_prefs.containsKey(storageKey)) {
        return const [];
      }
      final raw = _prefs.get(storageKey);
      if (raw == null) {
        return const [];
      }
      if (raw is! List) {
        throw const ShopStorageFailure(
            'Dữ liệu yêu thích bị sai định dạng bộ nhớ');
      }
      return List<String>.from(raw);
    } on ShopFailure {
      rethrow;
    } catch (e) {
      throw ShopStorageFailure('Lỗi đọc dữ liệu yêu thích từ thiết bị', e);
    }
  }

  @override
  Future<bool> isSaved(String productId) async {
    final list = await getSavedProductIds();
    return list.contains(productId);
  }

  @override
  Future<void> save(String productId) {
    return _enqueueWrite((current) {
      final updated = List<String>.from(current);
      updated.remove(productId);
      updated.insert(0, productId); // Newest at index 0
      return updated;
    });
  }

  @override
  Future<void> remove(String productId) {
    return _enqueueWrite((current) {
      final updated = List<String>.from(current);
      updated.remove(productId);
      return updated;
    });
  }

  @override
  Future<bool> toggle(String productId) async {
    bool wasSaved = false;
    await _enqueueWrite((current) {
      final updated = List<String>.from(current);
      if (updated.contains(productId)) {
        updated.remove(productId);
        wasSaved = false;
      } else {
        updated.insert(0, productId);
        wasSaved = true;
      }
      return updated;
    });
    return wasSaved;
  }

  @override
  Stream<List<String>> watchSavedProductIds() => _controller.stream;

  /// Serializes write operations through a chained Future queue to prevent race conditions.
  Future<void> _enqueueWrite(
      List<String> Function(List<String> current) modifier) {
    final completer = Completer<void>();

    // Chain execution to run after previous write completes, whether it succeeded or failed
    _writeQueue = _writeQueue.then((_) async {
      try {
        final current = await getSavedProductIds();
        final modified = modifier(current);

        final success = await _prefs.setStringList(storageKey, modified);
        if (!success) {
          throw const ShopStorageFailure(
              'Lưu trạng thái vào SharedPreferences trả về false');
        }

        // Only broadcast once persistent write succeeds
        _controller.add(List.unmodifiable(modified));
        completer.complete();
      } catch (e) {
        if (!completer.isCompleted) {
          if (e is ShopFailure) {
            completer.completeError(e);
          } else {
            completer.completeError(
                ShopStorageFailure('Lỗi ghi dữ liệu yêu thích', e));
          }
        }
      }
    }).catchError((_) {
      // Prevents unhandled error in the internal queue chain so subsequent writes can still proceed
    });

    return completer.future;
  }

  void dispose() {
    _controller.close();
  }
}
