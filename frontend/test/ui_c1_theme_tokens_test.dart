import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/membership/presentation/tokens/membership_tokens.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/onboarding_tokens.dart';
import 'package:health_ai_app/features/shop/presentation/theme/shop_theme.dart';
import 'package:health_ai_app/models/report_model.dart';
import 'package:health_ai_app/presentation/tokens/saman_workout_tokens.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/theme/nutrition_home_theme.dart';
import 'package:health_ai_app/widgets/saman_avatar.dart';
import 'package:health_ai_app/widgets/saman_feedback_snackbar.dart';
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

  group('UI-C1 Light Mode: Semantic Design System & Adaptive Tokens', () {
    testWidgets('SamanTheme.light() 1-to-1 Calm Athleticism Light component parity', (tester) async {
      final theme = SamanTheme.light();
      final ext = theme.extension<AppThemeExtension>()!;
      final palette = theme.extension<SamanPalette>()!;
      final darkPalette = SamanTheme.dark().extension<SamanPalette>()!;

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFEEF2F6));
      expect(theme.cardColor, const Color(0xFFFFFFFF));
      expect(theme.dividerColor, const Color(0xFFD5DCE6));

      expect(theme.colorScheme.primary, const Color(0xFF059669));
      expect(theme.colorScheme.onPrimary, const Color(0xFFFFFFFF));
      expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(theme.colorScheme.onSurface, const Color(0xFF0F172A));
      expect(theme.colorScheme.secondary, const Color(0xFF475569));
      expect(theme.colorScheme.outline, const Color(0xFFD5DCE6));
      expect(theme.colorScheme.surfaceContainerHighest, const Color(0xFFF1F5F9));
      expect(theme.colorScheme.error, const Color(0xFFDC2626));

      expect(ext.surfaceElevated, const Color(0xFFF1F5F9));
      expect(ext.inkMuted, const Color(0xFF475569));
      expect(ext.inkSubtle, const Color(0xFF64748B));
      expect(ext.hairline, const Color(0xFFD5DCE6));
      expect(ext.aiAccent, const Color(0xFFEA580C));
      expect(ext.warning, const Color(0xFFD97706));

      expect(palette.isDark, isFalse);
      expect(palette.canvas, const Color(0xFFEEF2F6));
      expect(palette.surface, const Color(0xFFFFFFFF));
      expect(palette.surfaceElevated, const Color(0xFFF1F5F9));
      expect(palette.border, const Color(0xFFD5DCE6));
      expect(palette.textPrimary, const Color(0xFF0F172A));
      expect(palette.textSecondary, const Color(0xFF475569));
      expect(palette.textMuted, const Color(0xFF64748B));
      expect(palette.accent, const Color(0xFF059669));
      expect(palette.onAccent, const Color(0xFFFFFFFF));
      expect(palette.amber, const Color(0xFFD97706));
      expect(palette.rose, const Color(0xFFE11D48));
      expect(palette.cyan, const Color(0xFF0891B2));
      expect(palette.danger, const Color(0xFFDC2626));

      expect(darkPalette.isDark, isTrue);
      expect(darkPalette.canvas, const Color(0xFF0C0D0E));
      expect(darkPalette.surface, const Color(0xFF16171B));
      expect(darkPalette.accent, const Color(0xFF10B981));

      expect(theme.textTheme.bodySmall?.color, const Color(0xFF475569));
      expect(theme.textTheme.labelSmall?.color, const Color(0xFF475569));

      expect(
        theme.appBarTheme.systemOverlayStyle?.statusBarBrightness,
        Brightness.light,
      );
      expect(
        theme.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
        Brightness.dark,
      );

      expect(
        theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
        const Color(0xFF059669),
      );
      expect(
        theme.elevatedButtonTheme.style?.foregroundColor?.resolve({}),
        const Color(0xFFFFFFFF),
      );
      expect(
        theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        const Color(0xFF059669),
      );
      expect(
        theme.filledButtonTheme.style?.foregroundColor?.resolve({}),
        const Color(0xFFFFFFFF),
      );
      expect(
        theme.outlinedButtonTheme.style?.foregroundColor?.resolve({}),
        const Color(0xFF0F172A),
      );
      expect(
        theme.outlinedButtonTheme.style?.side?.resolve({})?.color,
        const Color(0xFFD5DCE6),
      );
      expect(
        theme.inputDecorationTheme.fillColor,
        const Color(0xFFFFFFFF),
      );
      expect(
        theme.inputDecorationTheme.hintStyle?.color,
        const Color(0xFF64748B),
      );
      expect(
        theme.inputDecorationTheme.labelStyle?.color,
        const Color(0xFF475569),
      );
      expect(
        (theme.inputDecorationTheme.focusedBorder as OutlineInputBorder).borderSide.color,
        const Color(0xFF059669),
      );
      expect(theme.progressIndicatorTheme.color, const Color(0xFF059669));
      expect(theme.progressIndicatorTheme.linearTrackColor, const Color(0xFFD5DCE6));
      expect(theme.dialogTheme.backgroundColor, const Color(0xFFFFFFFF));
      expect(theme.dialogTheme.titleTextStyle?.color, const Color(0xFF0F172A));
      expect(theme.dialogTheme.contentTextStyle?.color, const Color(0xFF475569));
      expect(theme.snackBarTheme.backgroundColor, const Color(0xFFFFFFFF));
      expect(theme.bottomSheetTheme.backgroundColor, const Color(0xFFFFFFFF));
    });

    testWidgets('All 6 adaptive .of(context) token palettes + NutritionHomeStyle resolve Light & Dark', (tester) async {
      late SamanPalette lightSaman;
      late SamanHomePalette lightHome;
      late SamanChatPalette lightChat;
      late SamanWorkoutPalette lightWorkout;
      late MembershipPalette lightMembership;
      late OnboardingPalette lightOnboarding;
      late ShopPalette lightShop;
      late NutritionHomeStyle lightNutrition;
      late Color lightInsight;
      late Color lightTrack;

      await tester.pumpWidget(
        MaterialApp(
          theme: SamanTheme.light(),
          home: NutritionHomeTheme(
            child: Builder(
              builder: (context) {
                lightSaman = context.samanColors;
                lightHome = SamanHomeTokens.of(context);
                lightChat = SamanChatTokens.of(context);
                lightWorkout = SamanWorkoutTokens.of(context);
                lightMembership = MembershipTokens.of(context);
                lightOnboarding = OnboardingTokens.of(context);
                lightShop = ShopTheme.of(context);
                lightNutrition = NutritionHomeStyle.of(context);
                lightInsight = context.insightCardColor;
                lightTrack = context.trackColor;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(lightSaman.isDark, isFalse);
      expect(lightInsight, const Color(0xFFF1F5F9));
      expect(lightTrack, const Color(0xFFE2E8F0));

      expect(lightHome.canvas, const Color(0xFFF8FAFC));
      expect(lightHome.cardSurface, const Color(0xFFFFFFFF));
      expect(lightHome.textPrimary, const Color(0xFF0F172A));
      expect(lightHome.greenAccent, const Color(0xFF059669));

      expect(lightChat.canvas, const Color(0xFFF8FAFC));
      expect(lightChat.surface, const Color(0xFFFFFFFF));
      expect(lightChat.userBubble, const Color(0xFFF1F5F9));
      expect(lightChat.textPrimary, const Color(0xFF0F172A));

      expect(lightWorkout.canvas, const Color(0xFFF8FAFC));
      expect(lightWorkout.cardSurface, const Color(0xFFFFFFFF));
      expect(lightWorkout.emeraldAccent, const Color(0xFF059669));

      expect(lightMembership.canvas, const Color(0xFFF8FAFC));
      expect(lightMembership.card, const Color(0xFFFFFFFF));
      expect(lightMembership.accent, const Color(0xFF059669));

      expect(lightOnboarding.canvas, const Color(0xFFF8FAFC));
      expect(lightOnboarding.surface, const Color(0xFFFFFFFF));
      expect(lightOnboarding.textPrimary, const Color(0xFF0F172A));

      expect(lightShop.canvas, const Color(0xFFF8FAFC));
      expect(lightShop.surfaceCard, const Color(0xFFFFFFFF));
      expect(lightShop.emerald, const Color(0xFF059669));

      expect(lightNutrition.brightness, Brightness.light);
      expect(lightNutrition.canvas, const Color(0xFFF8FAFC));
      expect(lightNutrition.surface, const Color(0xFFFFFFFF));
      expect(lightNutrition.border, const Color(0xFFE2E8F0));
      expect(lightNutrition.ink, const Color(0xFF0F172A));
      expect(lightNutrition.muted, const Color(0xFF475569));
      expect(lightNutrition.accent, const Color(0xFF059669));
      expect(lightNutrition.onAccent, const Color(0xFFFFFFFF));
      expect(lightNutrition.track, const Color(0xFFE2E8F0));
      expect(lightNutrition.heroShadow, const Color(0xF2F8FAFC));

      // Verify Dark parity
      late SamanHomePalette darkHome;
      late SamanChatPalette darkChat;
      late SamanWorkoutPalette darkWorkout;
      late MembershipPalette darkMembership;
      late OnboardingPalette darkOnboarding;
      late ShopPalette darkShop;
      late NutritionHomeStyle darkNutrition;

      await tester.pumpWidget(
        MaterialApp(
          theme: SamanTheme.dark(),
          themeAnimationDuration: Duration.zero,
          home: NutritionHomeTheme(
            child: Builder(
              builder: (context) {
                darkHome = SamanHomeTokens.of(context);
                darkChat = SamanChatTokens.of(context);
                darkWorkout = SamanWorkoutTokens.of(context);
                darkMembership = MembershipTokens.of(context);
                darkOnboarding = OnboardingTokens.of(context);
                darkShop = ShopTheme.of(context);
                darkNutrition = NutritionHomeStyle.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(darkHome.canvas, SamanHomeTokens.canvas);
      expect(darkChat.userBubble, SamanChatTokens.userBubble);
      expect(darkWorkout.canvas, SamanWorkoutTokens.canvas);
      expect(darkMembership.canvas, MembershipTokens.canvas);
      expect(darkOnboarding.canvas, OnboardingTokens.canvas);
      expect(darkShop.canvas, ShopTheme.canvas);
      expect(darkNutrition.brightness, Brightness.dark);
      expect(darkNutrition.canvas, SamanHomeTokens.canvas);
      expect(darkNutrition.heroShadow, const Color(0xF20C0D0E));
    });

    testWidgets('SamanAvatar, SamanFeedbackSnackBar & WeeklyChart adapt to Light Mode', (tester) async {
      late SnackBar lightSnackBar;

      await tester.pumpWidget(
        MaterialApp(
          theme: SamanTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                lightSnackBar = SamanFeedbackSnackBar.build(
                  context: context,
                  message: 'Saved',
                  type: FeedbackType.success,
                );
                return Column(
                  children: [
                    const SamanAvatar(name: 'Saman User'),
                    WeeklyChart(
                      data: [
                        DailyReportItem(date: '2026-11-18', calories: 1800, protein: 120, water: 2000),
                        DailyReportItem(date: '2026-11-19', calories: 2100, protein: 140, water: 2200),
                      ],
                      targetValue: 2200,
                      label: 'Weekly Calories',
                      color: const Color(0xFF059669),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      final avatarContainer = tester.widget<Container>(
        find.descendant(of: find.byType(SamanAvatar), matching: find.byType(Container)).first,
      );
      final decoration = avatarContainer.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFF1F5F9));
      expect((decoration.border! as Border).top.color, const Color(0xFFE2E8F0));
      final initialsText = tester.widget<Text>(find.text('SU'));
      expect(initialsText.style?.color, const Color(0xFF0F172A));

      expect(lightSnackBar.backgroundColor, const Color(0xFFFFFFFF));
      final shape = lightSnackBar.shape! as RoundedRectangleBorder;
      expect(shape.side.color, const Color(0xFFE2E8F0));

      final linePainter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((cp) => cp.painter)
          .whereType<LineChartPainter>()
          .single;
      expect(linePainter.labelColor, const Color(0xFF475569));
      expect(linePainter.goalColor, const Color(0xFFDC2626));
    });
  });
}
