import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/domain/repositories/avatar_repository.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';

class CacheFixture implements ProfileRepository {
  ProfileSnapshot? cached;
  Completer<void>? cacheGate;
  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {
    await cacheGate?.future;
    cached = snapshot;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AvatarFixture implements AvatarRepository {
  int calls = 0;
  Completer<Map<String, dynamic>> response = Completer();
  @override
  Future<Map<String, dynamic>> uploadAvatar(XFile file, {bool Function()? isSessionCurrent}) {
    calls++;
    return response.future;
  }
  @override
  Future<Map<String, dynamic>> useGoogleAvatar({bool Function()? isSessionCurrent}) {
    calls++;
    return response.future;
  }
}

class NotifierFixture extends ProfileNotifier {
  NotifierFixture(super.repo, AvatarRepository avatar) : super(avatarRepository: avatar);
  void login(String owner) {
    state = ProfileState(status: ProfileStatus.ready, confirmedUserId: owner,
      isNetworkConfirmed: true, profile: const ProfileEntity(),
      snapshot: ProfileSnapshot(userId: owner, fullName: 'Same Name', profile: const ProfileEntity()));
  }
}

class GatedPreferences implements SharedPreferences {
  final values = <String, String>{};
  final gate = Completer<void>();
  final started = Completer<void>();
  bool blocked = false;
  @override
  Future<bool> setString(String key, String value) async {
    if (!blocked) {
      blocked = true; started.complete(); await gate.future;
    }
    values[key] = value;
    return true;
  }
  @override
  Future<bool> remove(String key) async { values.remove(key); return true; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const result = {'success': true, 'avatar': 'https://example.invalid/new.jpg',
  'avatar_source': 'custom', 'can_use_google_avatar': true};

void main() {
  test('unconfirmed identity never starts mutation', () async {
    final avatar = AvatarFixture();
    final notifier = NotifierFixture(CacheFixture(), avatar);
    addTearDown(notifier.dispose);
    expect(await notifier.uploadAvatar(XFile('unused')), false);
    expect(avatar.calls, 0);
  });
  test('double submit issues exactly one request', () async {
    final avatar = AvatarFixture(); final cache = CacheFixture();
    final notifier = NotifierFixture(cache, avatar)..login('A');
    addTearDown(notifier.dispose);
    final first = notifier.uploadAvatar(XFile('unused'));
    expect(await notifier.useGoogleAvatar(), false);
    avatar.response.complete(result);
    expect(await first, true);
    expect(avatar.calls, 1);
    expect(cache.cached?.avatar, result['avatar']);
  });
  for (final google in [false, true]) {
    test('late ${google ? 'Google' : 'upload'} response never updates B with same name', () async {
      final avatar = AvatarFixture(); final cache = CacheFixture();
      final notifier = NotifierFixture(cache, avatar)..login('A');
      addTearDown(notifier.dispose);
      final pending = google ? notifier.useGoogleAvatar() : notifier.uploadAvatar(XFile('unused'));
      notifier.resetSession(); notifier.login('B');
      avatar.response.complete(result);
      expect(await pending, false);
      expect(notifier.state.userId, 'B');
      expect(notifier.state.avatar, isNull);
      expect(cache.cached, isNull);
    });
  }
  test('logout during cache wait does not apply or report success', () async {
    final avatar = AvatarFixture(); final cache = CacheFixture()..cacheGate = Completer();
    final notifier = NotifierFixture(cache, avatar)..login('A');
    addTearDown(notifier.dispose);
    final pending = notifier.uploadAvatar(XFile('unused'));
    avatar.response.complete(result);
    await Future<void>.value();
    notifier.resetSession(); notifier.login('B');
    cache.cacheGate!.complete();
    expect(await pending, false);
    expect(notifier.state.avatar, isNull);
  });
  test('real cache FIFO clears pending A before writing B cache', () async {
    final prefs = GatedPreferences();
    final local = ProfileLocalDataSourceImpl(sharedPreferences: prefs);
    final pendingA = local.cacheSnapshot(const ProfileSnapshotModel(
      userId: 'A', profile: ProfileEntity(), avatar: 'https://example.invalid/A'));
    await prefs.started.future;
    final clearA = local.clearCache(userId: 'A');
    final pendingB = local.cacheSnapshot(const ProfileSnapshotModel(
      userId: 'B', profile: ProfileEntity(), avatar: 'https://example.invalid/B'));
    prefs.gate.complete();
    await Future.wait([pendingA, clearA, pendingB]);
    expect(prefs.values.containsKey(ProfileLocalDataSourceImpl.userSnapshotKey('A')), false);
    final shared = jsonDecode(prefs.values[ProfileLocalDataSourceImpl.cachedProfileSnapshotV2Key]!);
    expect(shared['user_id'], 'B');
  });
  test('unauthorized goes through existing Profile unauthorized state', () async {
    final avatar = AvatarFixture();
    final notifier = NotifierFixture(CacheFixture(), avatar)..login('A');
    addTearDown(notifier.dispose);
    final pending = notifier.useGoogleAvatar();
    avatar.response.completeError(const UnauthorizedException());
    expect(await pending, false);
    expect(notifier.state.isUnauthorized, true);
  });
  test('request guard runs after awaited auth interceptor and prevents dispatch', () async {
    final dio = Dio();
    final authRead = Completer<void>();
    var current = true; var sent = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      await authRead.future; handler.next(options);
    }));
    final remote = ProfileRemoteDataSourceImpl(dio: dio);
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent++; handler.resolve(Response(requestOptions: options, data: result, statusCode: 200));
    }));
    final pending = remote.useGoogleAvatar(isSessionCurrent: () => current);
    final assertion = expectLater(pending, throwsException);
    current = false; authRead.complete();
    await assertion;
    expect(sent, 0);
    dio.close();
  });
}
