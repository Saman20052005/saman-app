import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeNotifier', () {
    test(
      'fresh install defaults to ThemeMode.dark before and after _loadTheme()',
      () async {
        SharedPreferences.setMockInitialValues({});

        final notifier = ThemeNotifier();
        expect(notifier.state, ThemeMode.dark);

        await Future<void>.delayed(Duration.zero);
        expect(notifier.state, ThemeMode.dark);
      },
    );

    test(
      'restores ThemeMode.light when is_dark_mode is false',
      () async {
        SharedPreferences.setMockInitialValues({'is_dark_mode': false});

        final notifier = ThemeNotifier();
        await Future<void>.delayed(Duration.zero);

        expect(notifier.state, ThemeMode.light);
      },
    );

    test(
      'toggleTheme switches between dark and light and persists is_dark_mode',
      () async {
        SharedPreferences.setMockInitialValues({});

        final notifier = ThemeNotifier();
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state, ThemeMode.dark);

        await notifier.toggleTheme();
        expect(notifier.state, ThemeMode.light);
        final prefsAfterFirstToggle = await SharedPreferences.getInstance();
        expect(prefsAfterFirstToggle.getBool('is_dark_mode'), isFalse);

        await notifier.toggleTheme();
        expect(notifier.state, ThemeMode.dark);
        final prefsAfterSecondToggle = await SharedPreferences.getInstance();
        expect(prefsAfterSecondToggle.getBool('is_dark_mode'), isTrue);
      },
    );

    test(
      'setThemeMode persists light, dark, and system and restores from theme_mode',
      () async {
        SharedPreferences.setMockInitialValues({});

        final notifier = ThemeNotifier();
        await Future<void>.delayed(Duration.zero);

        await notifier.setThemeMode(ThemeMode.light);
        expect(notifier.state, ThemeMode.light);
        var prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), 'light');
        expect(prefs.getBool('is_dark_mode'), isFalse);

        await notifier.setThemeMode(ThemeMode.system);
        expect(notifier.state, ThemeMode.system);
        prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), 'system');

        final restoredSystem = ThemeNotifier();
        await Future<void>.delayed(Duration.zero);
        expect(restoredSystem.state, ThemeMode.system);

        await notifier.setThemeMode(ThemeMode.dark);
        expect(notifier.state, ThemeMode.dark);
        prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), 'dark');
        expect(prefs.getBool('is_dark_mode'), isTrue);
      },
    );
  });
}
