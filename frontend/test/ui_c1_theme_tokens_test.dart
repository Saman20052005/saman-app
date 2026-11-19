import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/models/report_model.dart';
import 'package:health_ai_app/presentation/tokens/saman_workout_tokens.dart';
import 'package:health_ai_app/screens/home/tokens/saman_home_tokens.dart';
import 'package:health_ai_app/widgets/weekly_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UI-C1: SamanTheme.dark() Calm Athleticism + WCAG AA', () {
    testWidgets('dark theme core palette, colorScheme, extensions, buttons, inputs, dialogs', (tester) async {
      final theme = SamanTheme.dark();
      final ext = theme.extension<AppThemeExtension>()!;

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0C0D0E));
      expect(theme.cardColor, const Color(0xFF16171B));
      expect(theme.dividerColor, const Color(0xFF26282F));

      expect(theme.colorScheme.primary, const Color(0xFF10B981));
      expect(theme.colorScheme.onPrimary, const Color(0xFF052E16));
      expect(theme.colorScheme.surface, const Color(0xFF16171B));
      expect(theme.colorScheme.onSurface, const Color(0xFFF9FAFB));
      expect(theme.colorScheme.secondary, const Color(0xFF9CA3AF));
      expect(theme.colorScheme.outline, const Color(0xFF26282F));
      expect(theme.colorScheme.surfaceContainerHighest, const Color(0xFF1E2026));

      expect(ext.surfaceElevated, const Color(0xFF1E2026));
      expect(ext.inkMuted, const Color(0xFF9CA3AF));
      expect(ext.inkSubtle, const Color(0xFF6B7280));
      expect(ext.hairline, const Color(0xFF26282F));

      expect(theme.textTheme.titleMedium?.color, const Color(0xFFF9FAFB));
      expect(theme.textTheme.titleSmall?.color, const Color(0xFFF9FAFB));
      expect(theme.textTheme.bodySmall?.color, const Color(0xFF9CA3AF));
      expect(theme.textTheme.labelLarge?.color, const Color(0xFFF9FAFB));
      expect(theme.textTheme.labelSmall?.color, const Color(0xFF9CA3AF));

      expect(
        theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
        const Color(0xFF10B981),
      );
      expect(
        theme.elevatedButtonTheme.style?.foregroundColor?.resolve({}),
        const Color(0xFF052E16),
      );
      expect(
        theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        const Color(0xFF10B981),
      );
      expect(
        theme.filledButtonTheme.style?.foregroundColor?.resolve({}),
        const Color(0xFF052E16),
      );
      expect(
        theme.floatingActionButtonTheme.backgroundColor,
        const Color(0xFF10B981),
      );
      expect(
        theme.floatingActionButtonTheme.foregroundColor,
        const Color(0xFF052E16),
      );
      expect(
        theme.outlinedButtonTheme.style?.foregroundColor?.resolve({}),
        const Color(0xFFF9FAFB),
      );
      expect(
        theme.outlinedButtonTheme.style?.side?.resolve({})?.color,
        const Color(0xFF26282F),
      );

      expect(theme.inputDecorationTheme.fillColor, const Color(0xFF16171B));
      expect(theme.inputDecorationTheme.hintStyle?.color, const Color(0xFF6B7280));
      expect(theme.inputDecorationTheme.labelStyle?.color, const Color(0xFF9CA3AF));
      expect(
        (theme.inputDecorationTheme.enabledBorder as OutlineInputBorder).borderSide.color,
        const Color(0xFF26282F),
      );
      final focused = theme.inputDecorationTheme.focusedBorder as OutlineInputBorder;
      expect(focused.borderSide.color, const Color(0xFF10B981));
      expect(focused.borderSide.width, 1.5);

      expect(theme.progressIndicatorTheme.color, const Color(0xFF10B981));
      expect(theme.progressIndicatorTheme.linearTrackColor, const Color(0xFF26282F));

      expect(theme.dialogTheme.backgroundColor, const Color(0xFF1E2026));
      expect(theme.dialogTheme.titleTextStyle?.color, const Color(0xFFF9FAFB));
      expect(theme.dialogTheme.contentTextStyle?.color, const Color(0xFF9CA3AF));
      expect(theme.bottomSheetTheme.backgroundColor, const Color(0xFF1E2026));
    });

    testWidgets('light theme remains preserved', (tester) async {
      final light = SamanTheme.light();
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, AppColors.canvas);
      expect(light.colorScheme.primary, AppColors.primary);
      expect(light.colorScheme.onPrimary, AppColors.onPrimary);
    });

    test('token contrast upgrades in SamanHomeTokens & SamanWorkoutTokens', () {
      expect(SamanHomeTokens.textTertiary, const Color(0xFF6B7280));
      expect(SamanWorkoutTokens.textMuted, const Color(0xFF9CA3AF));
    });

    testWidgets('SamanColors extension & WeeklyChart use dark WCAG AA colors', (tester) async {
      Color? insightColor;
      Color? trackColor;

      await tester.pumpWidget(
        MaterialApp(
          theme: SamanTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                insightColor = context.insightCardColor;
                trackColor = context.trackColor;
                return WeeklyChart(
                  data: [
                    DailyReportItem(date: '2026-11-18', calories: 1800, protein: 120, water: 2000),
                    DailyReportItem(date: '2026-11-19', calories: 2100, protein: 140, water: 2200),
                  ],
                  targetValue: 2200,
                  label: 'Weekly Calories',
                  color: const Color(0xFF10B981),
                );
              },
            ),
          ),
        ),
      );

      expect(insightColor, const Color(0xFF1E2026));
      expect(trackColor, const Color(0xFF26282F));

      final titleWidget = tester.widget<Text>(find.text('Weekly Calories'));
      expect(titleWidget.style?.color, const Color(0xFFF9FAFB));

      final goalLegend = tester.widget<Text>(find.text('Goal'));
      expect(goalLegend.style?.color, const Color(0xFF9CA3AF));

      final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final linePainter = customPaints
          .map((cp) => cp.painter)
          .whereType<LineChartPainter>()
          .single;
      expect(linePainter.labelColor, const Color(0xFF9CA3AF));
    });
  });
}
