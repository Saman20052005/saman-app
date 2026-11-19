import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../config/api_config.dart';
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

  final Dio? _dio;
  final String _baseUrl;
  final bool _syncEnabled;

  SharedPreferencesShopWishlistRepository(
    this._prefs, {
    Dio? dio,
    String? baseUrl,
    bool syncEnabled = false,
  })  : _dio = dio,
        _baseUrl = (baseUrl ?? '').replaceAll(RegExp(r'/+$'), ''),
        _syncEnabled = syncEnabled;

  String get _effectiveBaseUrl =>
      _baseUrl.isEmpty ? ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '') : _baseUrl;

  Future<void> syncFromRemote() async {
    if (!_syncEnabled || _dio == null) return;

    // Join the same FIFO queue as local writes so the merge sees the latest
    // bookmarks and cannot overwrite a concurrent tap.
    final queued = _writeQueue.then((_) async {
      try {
        final response = await _dio.get('$_effectiveBaseUrl/api/shop/wishlist');
        final data = response.data;
        if (data is! Map || data['saved_product_ids'] is! List) return;

        final remoteIds = List<String>.from(data['saved_product_ids'] as List);
        final localIds = await getSavedProductIds();
        final merged = <String>[
          ...localIds,
          ...remoteIds.where((id) => !localIds.contains(id)),
        ];

        final success = await _prefs.setStringList(storageKey, merged);
        if (!success) return;
        _controller.add(List.unmodifiable(merged));

        if (!_sameIds(merged, remoteIds)) {
          await _pushRemote(merged);
        }
      } catch (_) {
        // Remote sync is best-effort; the local wishlist remains usable.
      }
    });
    _writeQueue = queued.catchError((_) {});
    await _writeQueue;
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _pushRemote(List<String> ids) async {
    await _dio!.put(
      '$_effectiveBaseUrl/api/shop/wishlist',
      data: {'saved_product_ids': ids},
    );
  }

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
        if (_syncEnabled && _dio != null) {
          unawaited(_pushRemote(modified).catchError((_) {}));
        }
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
