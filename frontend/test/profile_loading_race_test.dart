import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/providers/profile_provider.dart';

class _MockProfileRepository implements ProfileRepository {
  int fetchCount = 0;
  Completer<ProfileSnapshot?>? completer;
  final List<ProfileSnapshot> cachedSnapshots = [];
  final List<Completer<ProfileSnapshot?>> queuedCompleters = [];
  final Map<String, Completer<void>> cacheCompleters = {};
  Future<void> _mutationQueue = Future.value();
  Object? errorToThrow;
  ProfileSnapshot? snapshotToReturn;

  Future<T> _enqueueMutation<T>(Future<T> Function() op) {
    final next = _mutationQueue.then((_) => op(), onError: (_) => op());
    _mutationQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async {
    fetchCount++;
    if (queuedCompleters.isNotEmpty) {
      return queuedCompleters.removeAt(0).future;
    }
    if (completer != null) {
      return completer!.future;
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return snapshotToReturn;
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) {
    return _enqueueMutation(() async {
      final key = snapshot.fullName ?? snapshot.email ?? 'default';
      if (cacheCompleters.containsKey(key)) {
        await cacheCompleters[key]!.future;
      }
      cachedSnapshots.add(snapshot);
    });
  }

  @override
  Future<ProfileEntity?> fetchProfile() async => snapshotToReturn?.profile;

  @override
  Future<void> syncProfile(ProfileEntity profile) async {}

  @override
  Future<void> clearLocalProfile() {
    return _enqueueMutation(() async {
      cachedSnapshots.clear();
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileNotifier - Loading Race and Deduplication', () {
    test(
        'deduplicates concurrent loadProfile calls into a single network invocation',
        () async {
      final repo = _MockProfileRepository();
      final completer = Completer<ProfileSnapshot?>();
      repo.completer = completer;

      final notifier = ProfileNotifier(repo);

      // Trigger 3 concurrent calls
      final f1 = notifier.loadProfile();
      final f2 = notifier.loadProfile();
      final f3 = notifier.loadProfile();

      expect(notifier.state.status, equals(ProfileStatus.loading));
      expect(repo.fetchCount, equals(1));

      // Complete the single in-flight request
      completer.complete(
        const ProfileSnapshot(
          profile: ProfileEntity(
            age: 25,
            height: 175.0,
            weight: 70.0,
          ),
          targetCalories: 2200,
        ),
      );

      await Future.wait([f1, f2, f3]);

      expect(repo.fetchCount, equals(1));
      expect(notifier.state.status, equals(ProfileStatus.ready));
      expect(notifier.state.targetCalories, equals(2200));
    });

    test('discards late responses if session is reset during in-flight load',
        () async {
      final repo = _MockProfileRepository();
      final completer = Completer<ProfileSnapshot?>();
      repo.completer = completer;

      final notifier = ProfileNotifier(repo);

      // Start loading in session 0
      final loadFuture = notifier.loadProfile();
      expect(notifier.state.status, equals(ProfileStatus.loading));

      // User logs out, resetting session epoch
      notifier.resetSession();
      expect(notifier.state.status, equals(ProfileStatus.initial));

      // Old request finally resolves late
      completer.complete(
        const ProfileSnapshot(
          profile: ProfileEntity(age: 30, height: 180, weight: 80),
          targetCalories: 2500,
        ),
      );

      await loadFuture;

      // Old response must NOT overwrite initial state of new session
      expect(notifier.state.status, equals(ProfileStatus.initial));
      expect(notifier.state.profile.isValid, isFalse);
    });

    test(
        'cross-session race: Account A request resolving late cannot overwrite Account B state or cache, and Request B starts immediately',
        () async {
      final repo = _MockProfileRepository();
      final completerA = Completer<ProfileSnapshot?>();
      final completerB = Completer<ProfileSnapshot?>();
      repo.queuedCompleters.addAll([completerA, completerB]);

      final notifier = ProfileNotifier(repo);

      // 1. Account A starts loadProfile() in session 0
      final futureA = notifier.loadProfile();
      expect(repo.fetchCount, equals(1));
      expect(notifier.sessionEpoch, equals(0));

      // 2. User logs out -> Profile session resets to session 1
      notifier.resetSession();
      expect(notifier.sessionEpoch, equals(1));
      expect(notifier.state.status, equals(ProfileStatus.initial));

      // 3. Account B logs in immediately and starts loadProfile()
      final futureB = notifier.loadProfile();
      // Proves Request B starts immediately and does not await or reuse Request A
      expect(repo.fetchCount, equals(2));

      // 4. Response A arrives late with Account A data
      const snapshotA = ProfileSnapshot(
        profile: ProfileEntity(age: 21, height: 168, weight: 60),
        targetCalories: 1600,
      );
      completerA.complete(snapshotA);
      await futureA;

      // Proves Response A NEVER touched persistent cache or active state
      expect(repo.cachedSnapshots, isEmpty);
      expect(notifier.state.status, equals(ProfileStatus.loading));
      expect(notifier.state.profile.isValid, isFalse);

      // 5. Response B arrives with Account B data
      const snapshotB = ProfileSnapshot(
        profile: ProfileEntity(age: 32, height: 182, weight: 85),
        targetCalories: 2800,
      );
      completerB.complete(snapshotB);
      await futureB;

      // Proves Response B wins, updates state, and commits to cache
      expect(notifier.state.status, equals(ProfileStatus.ready));
      expect(notifier.state.profile.age, equals(32));
      expect(notifier.state.targetCalories, equals(2800));
      expect(repo.cachedSnapshots.length, equals(1));
      expect(repo.cachedSnapshots.first.targetCalories, equals(2800));

      // Proves _ongoingLoad was cleanly disposed and a subsequent load works
      repo.snapshotToReturn = snapshotB;
      await notifier.loadProfile();
      expect(repo.fetchCount, equals(3));
    });

    test(
        'deterministic concurrency: logout during paused cache write A cannot allow A to overwrite cache or state, and Account B wins',
        () async {
      final repo = _MockProfileRepository();
      final completerRemoteA = Completer<ProfileSnapshot?>();
      final completerRemoteB = Completer<ProfileSnapshot?>();
      repo.queuedCompleters.addAll([completerRemoteA, completerRemoteB]);

      // Pause cache write for Account A
      final pauseCacheA = Completer<void>();
      repo.cacheCompleters['AccountA'] = pauseCacheA;

      final notifier = ProfileNotifier(repo);

      // 1. Account A begins Profile load
      final futureA = notifier.loadProfile();
      expect(repo.fetchCount, equals(1));
      expect(notifier.sessionEpoch, equals(0));

      // 2. Remote response A completes
      const snapshotA = ProfileSnapshot(
        fullName: 'AccountA',
        profile: ProfileEntity(age: 22, height: 170, weight: 65),
        targetCalories: 1700,
      );
      completerRemoteA.complete(snapshotA);
      // Allow execution to reach cacheSnapshot(A) and pause on pauseCacheA
      await Future.delayed(Duration.zero);

      // 3. Cache write A is now actively awaiting in queue on pauseCacheA
      // 4. Logout / reset begins: epoch resets, clearLocalProfile is enqueued in FIFO mutation queue
      notifier.resetSession();
      expect(notifier.sessionEpoch, equals(1));
      expect(notifier.state.status, equals(ProfileStatus.initial));
      final clearFuture = repo.clearLocalProfile();

      // 5. Account B begins a new Profile load in session 1
      final futureB = notifier.loadProfile();
      expect(repo.fetchCount, equals(2));

      // 6. Remote response B completes
      const snapshotB = ProfileSnapshot(
        fullName: 'AccountB',
        profile: ProfileEntity(age: 33, height: 180, weight: 80),
        targetCalories: 2600,
      );
      completerRemoteB.complete(snapshotB);

      // 7. Release cache write A (simulating delayed completion of A's write)
      pauseCacheA.complete();

      // Await all futures to settle
      await futureA;
      await clearFuture;
      await futureB;

      // 8. Final state belongs ONLY to Account B
      expect(notifier.state.status, equals(ProfileStatus.ready));
      expect(notifier.state.profile.age, equals(33));
      expect(notifier.state.targetCalories, equals(2600));

      // 9. Final persistent cache belongs ONLY to Account B
      expect(repo.cachedSnapshots.length, equals(1));
      expect(repo.cachedSnapshots.first.fullName, equals('AccountB'));
      expect(repo.cachedSnapshots.first.targetCalories, equals(2600));

      // 10. Account A data is completely absent from cache and state
      expect(
          repo.cachedSnapshots.any((s) => s.fullName == 'AccountA'), isFalse);
      expect(notifier.state.targetCalories, isNot(equals(1700)));
    });

    test(
        'deterministic concurrency: logout during paused cache write A without Account B leaves cache and state clean',
        () async {
      final repo = _MockProfileRepository();
      final completerRemoteA = Completer<ProfileSnapshot?>();
      repo.queuedCompleters.add(completerRemoteA);

      final pauseCacheA = Completer<void>();
      repo.cacheCompleters['AccountA'] = pauseCacheA;

      final notifier = ProfileNotifier(repo);

      // 1. Account A begins Profile load
      final futureA = notifier.loadProfile();

      // 2. Remote response A completes
      const snapshotA = ProfileSnapshot(
        fullName: 'AccountA',
        profile: ProfileEntity(age: 22, height: 170, weight: 65),
        targetCalories: 1700,
      );
      completerRemoteA.complete(snapshotA);
      await Future.delayed(Duration.zero);

      // 3. User logs out while cache write A is in flight
      notifier.resetSession();
      final clearFuture = repo.clearLocalProfile();

      // 4. Cache write A finishes after logout
      pauseCacheA.complete();

      await futureA;
      await clearFuture;

      // Final state is initial
      expect(notifier.state.status, equals(ProfileStatus.initial));
      expect(notifier.state.profile.isValid, isFalse);

      // Cache is completely empty
      expect(repo.cachedSnapshots, isEmpty);
    });

    test(
        'sets status to unauthorized when UnauthorizedException is encountered',
        () async {
      final repo = _MockProfileRepository();
      repo.errorToThrow = const UnauthorizedException('Token expired');

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      expect(notifier.state.status, equals(ProfileStatus.unauthorized));
      expect(notifier.state.isUnauthorized, isTrue);
    });

    test(
        'sets status to incomplete when profile snapshot is null (e.g. 404/empty)',
        () async {
      final repo = _MockProfileRepository();
      repo.snapshotToReturn = null;

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      expect(notifier.state.status, equals(ProfileStatus.incomplete));
      expect(notifier.state.isIncomplete, isTrue);
    });

    test('sets status to offline when snapshot comes from cache fallback',
        () async {
      final repo = _MockProfileRepository();
      repo.snapshotToReturn = const ProfileSnapshot(
        profile: ProfileEntity(age: 28, height: 175, weight: 70),
        targetCalories: 2100,
        isFromCache: true,
      );

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      expect(notifier.state.status, equals(ProfileStatus.offline));
      expect(notifier.state.isOffline, isTrue);
      expect(notifier.state.isFromCache, isTrue);
    });

    test(
        'sets status to error when generic network failure occurs without cache',
        () async {
      final repo = _MockProfileRepository();
      repo.errorToThrow = Exception('Network connection timed out');

      final notifier = ProfileNotifier(repo);
      await notifier.loadProfile();

      expect(notifier.state.status, equals(ProfileStatus.error));
      expect(notifier.state.hasError, isTrue);
    });
  });
}
