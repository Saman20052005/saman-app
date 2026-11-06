import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'avatar_session_isolation_test.dart' show AvatarFixture, CacheFixture, NotifierFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/image_picker');
  late Directory images;
  late File photo;
  late AvatarFixture avatar;
  late CacheFixture cache;
  late NotifierFixture notifier;
  late ProviderContainer container;
  var retrieves = 0;
  Completer<Object?>? lost;

  setUp(() {
    images = Directory('D:/SamanDev/runtime_evidence/avatar_codex/recovery-images')..createSync(recursive: true);
    photo = File('D:/SamanDev/runtime_evidence/avatar_codex/recovery-images/fixture.png');
    photo.writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg=='));
    avatar = AvatarFixture(); cache = CacheFixture();
    notifier = NotifierFixture(cache, avatar);
    container = ProviderContainer(overrides: [profileRepositoryProvider.overrideWithValue(cache),
      avatarRepositoryProvider.overrideWithValue(avatar), profileProvider.overrideWith((ref) => notifier)]);
    retrieves = 0; lost = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'retrieve') { retrieves++; return lost == null ? null : await lost!.future; }
      if (call.method == 'pickImage') return photo.path;
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'pending_avatar_picker_user': 'A',
      'pending_avatar_picker_timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  });
  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    if (photo.existsSync()) photo.deleteSync();
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: ProfileScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('restore waits for confirmed ID and preserves marker during initial state', (tester) async {
    await show(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pending_avatar_picker_user'), 'A');
    expect(retrieves, 0);
    notifier.login('A');
    await tester.pumpAndSettle();
    expect(retrieves, 1);
  });
  testWidgets('same display name on B does not consume A lost data', (tester) async {
    notifier.login('B');
    await show(tester);
    expect(retrieves, 0);
    expect(find.byKey(const Key('confirm_save_avatar_button')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pending_avatar_picker_user'), isNull);
  });
  testWidgets('session changes while retrieve awaits do not open preview or upload', (tester) async {
    notifier.login('A'); lost = Completer<Object?>();
    await show(tester);
    expect(retrieves, 1);
    notifier.resetSession(); notifier.login('B');
    lost!.complete({'path': photo.path, 'type': 'image'});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm_save_avatar_button')), findsNothing);
    expect(avatar.calls, 0);
  });
  testWidgets('recovered file opens preview only; account switch removes that preview', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_avatar_picker_path', photo.path);
    notifier.login('A');
    await show(tester);
    expect(find.byKey(const Key('confirm_save_avatar_button')), findsOneWidget);
    expect(avatar.calls, 0);
    notifier.resetSession(); notifier.login('B');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm_save_avatar_button')), findsNothing);
    expect(avatar.calls, 0);
  });
  testWidgets('disposing Profile preserves pending preview for remount', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_avatar_picker_path', photo.path);
    notifier.login('A'); await show(tester);
    await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
    expect(prefs.getString('pending_avatar_picker_user'), 'A');
    expect(prefs.getString('pending_avatar_picker_path'), photo.path);
    await show(tester);
    expect(find.byKey(const Key('confirm_save_avatar_button')), findsOneWidget);
    expect(avatar.calls, 0);
  });
}
