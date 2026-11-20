import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_metadata.dart';
import '../../config/app_theme.dart';
import '../../config/app_translations.dart';
import '../../config/theme_provider.dart';
import '../../services/unit_converter.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  static const String routeName = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.samanColors;
    final locale = ref.watch(languageProvider);
    final languageMode = ref.watch(languageModeProvider);
    final unitSystem = ref.watch(unitProvider);
    final isDarkMode = ref.watch(themeProvider) == ThemeMode.dark;
    final appVersion = ref.watch(appVersionProvider);

    // Resolve displayed language label
    final String currentLanguageDisplay = switch (languageMode) {
      AppLanguageMode.system =>
        locale.languageCode == 'vi' ? 'Tiếng Việt' : 'English',
      AppLanguageMode.vi => 'Tiếng Việt',
      AppLanguageMode.en => 'English',
    };

    // Resolve displayed unit label
    final String currentUnitDisplay = unitSystem == UnitSystem.imperial
        ? AppTranslations.text('unit_imperial', locale)
        : AppTranslations.text('unit_metric', locale);

    final String unitSubtitle = unitSystem == UnitSystem.imperial
        ? AppTranslations.text('units_sub_imperial', locale)
        : AppTranslations.text('units_sub_metric', locale);

    return Scaffold(
      backgroundColor:
          palette.isDark ? const Color(0xFF0A0A0C) : palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            _buildTopNavBar(context, locale),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // SECTION 1: PREFERENCES
                    _buildSectionHeader(
                      context,
                      AppTranslations.text('preferences', locale),
                    ),
                    _buildCardGroup(
                      context,
                      children: [
                        // Row: Language
                        _buildSettingsRow(
                          context: context,
                          key: const Key('setting_row_language'),
                          icon: Icons.public_outlined,
                          title: 'Ngôn ngữ / Language',
                          value: currentLanguageDisplay,
                          showChevron: true,
                          onTap: () => _openLanguageSheet(context, ref, locale),
                        ),
                        _buildDivider(context),
                        // Row: Units
                        _buildSettingsRow(
                          context: context,
                          key: const Key('setting_row_units'),
                          icon: Icons.straighten_outlined,
                          title: AppTranslations.text('units', locale),
                          subtitle: unitSubtitle,
                          value: currentUnitDisplay,
                          showChevron: true,
                          onTap: () => _openUnitsSheet(context, ref, locale),
                        ),
                        _buildDivider(context),
                        // Row: Dark Mode
                        _buildSettingsRow(
                          context: context,
                          key: const Key('setting_row_dark_mode'),
                          icon: Icons.dark_mode_outlined,
                          title: locale.languageCode == 'vi'
                              ? 'Giao diện tối'
                              : 'Dark Mode',
                          subtitle: locale.languageCode == 'vi'
                              ? (isDarkMode ? 'Đang bật' : 'Đang tắt')
                              : (isDarkMode ? 'On' : 'Off'),
                          showChevron: false,
                          onTap: () =>
                              ref.read(themeProvider.notifier).toggleTheme(),
                          trailing: Switch(
                            key: const Key('setting_switch_dark_mode'),
                            value: isDarkMode,
                            onChanged: (_) =>
                                ref.read(themeProvider.notifier).toggleTheme(),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            activeColor: palette.onAccent,
                            activeTrackColor: palette.accent,
                            inactiveThumbColor: palette.isDark
                                ? const Color(0xFF8E8E93)
                                : palette.textMuted,
                            inactiveTrackColor: palette.isDark
                                ? const Color(0xFF27272A)
                                : palette.surfaceElevated,
                            trackOutlineColor:
                                WidgetStateProperty.resolveWith<Color?>(
                              (states) => states.contains(WidgetState.selected)
                                  ? Colors.transparent
                                  : (palette.isDark
                                      ? const Color(0x14FFFFFF)
                                      : palette.border),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // SECTION 2: ABOUT SAMAN
                    _buildSectionHeader(
                      context,
                      AppTranslations.text('about_saman', locale),
                    ),
                    _buildCardGroup(
                      context,
                      children: [
                        // Row: Privacy Policy
                        _buildSettingsRow(
                          context: context,
                          key: const Key('link_privacy_policy'),
                          icon: Icons.shield_outlined,
                          title: AppTranslations.text('privacy_policy', locale),
                          showChevron: true,
                          onTap: () => _showNotConfiguredDialog(
                            context: context,
                            title: AppTranslations.text(
                              'privacy_policy',
                              locale,
                            ),
                            message: AppTranslations.text(
                              'privacy_not_configured_desc',
                              locale,
                            ),
                            icon: Icons.shield_outlined,
                            locale: locale,
                          ),
                        ),
                        _buildDivider(context),
                        // Row: Terms of Service
                        _buildSettingsRow(
                          context: context,
                          key: const Key('link_terms_of_service'),
                          icon: Icons.description_outlined,
                          title:
                              AppTranslations.text('terms_of_service', locale),
                          showChevron: true,
                          onTap: () => _showNotConfiguredDialog(
                            context: context,
                            title: AppTranslations.text(
                              'terms_of_service',
                              locale,
                            ),
                            message: AppTranslations.text(
                              'terms_not_configured_desc',
                              locale,
                            ),
                            icon: Icons.description_outlined,
                            locale: locale,
                          ),
                        ),
                        _buildDivider(context),
                        // Row: Help & Support
                        _buildSettingsRow(
                          context: context,
                          key: const Key('link_help_support'),
                          icon: Icons.help_outline_rounded,
                          title: AppTranslations.text('help_support', locale),
                          showChevron: true,
                          onTap: () => _showNotConfiguredDialog(
                            context: context,
                            title: AppTranslations.text('help_support', locale),
                            message: AppTranslations.text(
                              'help_not_configured_desc',
                              locale,
                            ),
                            icon: Icons.help_outline_rounded,
                            locale: locale,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // SECTION 3: APP INFORMATION
                    _buildSectionHeader(
                      context,
                      AppTranslations.text('app_information', locale),
                    ),
                    _buildCardGroup(
                      context,
                      children: [
                        // Row: App version (Read-only, no chevron)
                        _buildSettingsRow(
                          context: context,
                          key: const Key('info_row_version'),
                          icon: Icons.info_outline_rounded,
                          title: AppTranslations.text('app_version', locale),
                          value: appVersion,
                          showChevron: false,
                          isReadOnly: true,
                        ),
                      ],
                    ),

                    // Screen Footer
                    const SizedBox(height: 36),
                    Center(
                      child: Text(
                        AppTranslations.text('app_tagline', locale),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: palette.textMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Top Navigation Bar ---
  Widget _buildTopNavBar(BuildContext context, Locale locale) {
    final palette = context.samanColors;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('app_settings_back_button'),
            icon: Icon(
              Icons.chevron_left_rounded,
              color: textPrimary,
              size: 28,
            ),
            splashRadius: 24,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              AppTranslations.text('app_settings', locale),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Section Header ---
  Widget _buildSectionHeader(BuildContext context, String title) {
    final palette = context.samanColors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: palette.isDark ? const Color(0xFF8E8E93) : palette.textMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // --- Grouped Card Container ---
  Widget _buildCardGroup(BuildContext context, {required List<Widget> children}) {
    final palette = context.samanColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.isDark ? const Color(0xFF151518) : palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.isDark ? const Color(0x14FFFFFF) : palette.border,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  // --- Divider ---
  Widget _buildDivider(BuildContext context) {
    final palette = context.samanColors;
    return Divider(
      color: palette.isDark ? const Color(0x0FFFFFFF) : palette.borderSubtle,
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
    );
  }

  // --- Setting Row ---
  Widget _buildSettingsRow({
    required BuildContext context,
    Key? key,
    required IconData icon,
    required String title,
    String? subtitle,
    String? value,
    Widget? trailing,
    bool showChevron = true,
    bool isReadOnly = false,
    VoidCallback? onTap,
  }) {
    final palette = context.samanColors;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    final mutedColor =
        palette.isDark ? const Color(0xFF8E8E93) : palette.textSecondary;
    final chevronColor =
        palette.isDark ? const Color(0xFF9CA3AF) : palette.textMuted;
    final valueColor = palette.isDark
        ? (isReadOnly ? const Color(0xFF9CA3AF) : const Color(0xFF8E8E93))
        : palette.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: isReadOnly ? null : onTap,
        splashColor: palette.isDark
            ? Colors.white.withOpacity(0.04)
            : palette.textPrimary.withOpacity(0.05),
        highlightColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leading Icon
              Icon(
                icon,
                size: 20,
                color: mutedColor,
              ),
              const SizedBox(width: 14),

              // Title and optional subtitle + trailing value within flexible layout
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: subtitle != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: textPrimary,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: mutedColor,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: textPrimary,
                                letterSpacing: -0.1,
                              ),
                            ),
                    ),
                    if (value != null) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: valueColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Trailing Widget or Chevron
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ] else if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: chevronColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Language Bottom Sheet ---
  void _openLanguageSheet(
      BuildContext context, WidgetRef ref, Locale currentLocale) {
    final palette = context.samanColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          palette.isDark ? const Color(0xFF151518) : palette.surface,
      barrierColor: Colors.black.withOpacity(palette.isDark ? 0.6 : 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, refConsumer, _) {
            final sheetPalette = context.samanColors;
            final textPrimary =
                sheetPalette.isDark ? Colors.white : sheetPalette.textPrimary;
            final handleColor = sheetPalette.isDark
                ? const Color(0x33FFFFFF)
                : sheetPalette.border;
            final activeMode = refConsumer.watch(languageModeProvider);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: handleColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sheet Title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          AppTranslations.text(
                              'language_setting', currentLocale),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Option 1: Use device language
                    _buildSheetOptionTile(
                      context: context,
                      key: const Key('language_option_system'),
                      title: AppTranslations.text(
                          'use_device_language', currentLocale),
                      subtitle: AppTranslations.text(
                          'device_language_sub', currentLocale),
                      isSelected: activeMode == AppLanguageMode.system,
                      onTap: () async {
                        await refConsumer
                            .read(languageProvider.notifier)
                            .setLanguageMode(AppLanguageMode.system);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),

                    // Option 2: Tiếng Việt
                    _buildSheetOptionTile(
                      context: context,
                      key: const Key('language_option_vi'),
                      title: 'Tiếng Việt',
                      subtitle: 'Vietnamese',
                      isSelected: activeMode == AppLanguageMode.vi,
                      onTap: () async {
                        await refConsumer
                            .read(languageProvider.notifier)
                            .setLanguageMode(AppLanguageMode.vi);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),

                    // Option 3: English
                    _buildSheetOptionTile(
                      context: context,
                      key: const Key('language_option_en'),
                      title: 'English',
                      subtitle: 'Tiếng Anh',
                      isSelected: activeMode == AppLanguageMode.en,
                      onTap: () async {
                        await refConsumer
                            .read(languageProvider.notifier)
                            .setLanguageMode(AppLanguageMode.en);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Units Bottom Sheet ---
  void _openUnitsSheet(
      BuildContext context, WidgetRef ref, Locale currentLocale) {
    final palette = context.samanColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          palette.isDark ? const Color(0xFF151518) : palette.surface,
      barrierColor: Colors.black.withOpacity(palette.isDark ? 0.6 : 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, refConsumer, _) {
            final sheetPalette = context.samanColors;
            final textPrimary =
                sheetPalette.isDark ? Colors.white : sheetPalette.textPrimary;
            final handleColor = sheetPalette.isDark
                ? const Color(0x33FFFFFF)
                : sheetPalette.border;
            final activeUnit = refConsumer.watch(unitProvider);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: handleColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sheet Title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          AppTranslations.text('units', currentLocale),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Option 1: Metric
                    _buildSheetOptionTile(
                      context: context,
                      key: const Key('unit_option_metric'),
                      title:
                          AppTranslations.text('metric_label', currentLocale),
                      isSelected: activeUnit == UnitSystem.metric,
                      onTap: () async {
                        await refConsumer
                            .read(unitProvider.notifier)
                            .setUnitSystem(UnitSystem.metric);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),

                    // Option 2: Imperial
                    _buildSheetOptionTile(
                      context: context,
                      key: const Key('unit_option_imperial'),
                      title:
                          AppTranslations.text('imperial_label', currentLocale),
                      isSelected: activeUnit == UnitSystem.imperial,
                      onTap: () async {
                        await refConsumer
                            .read(unitProvider.notifier)
                            .setUnitSystem(UnitSystem.imperial);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Bottom Sheet Option Tile ---
  Widget _buildSheetOptionTile({
    required BuildContext context,
    Key? key,
    required String title,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final palette = context.samanColors;
    final selectedText = palette.isDark ? Colors.white : palette.textPrimary;
    final unselectedText =
        palette.isDark ? const Color(0xFFD4D4D8) : palette.textSecondary;
    final subtitleColor =
        palette.isDark ? const Color(0xFF8E8E93) : palette.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        splashColor: palette.isDark
            ? Colors.white.withOpacity(0.04)
            : palette.textPrimary.withOpacity(0.05),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? selectedText : unselectedText,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_rounded,
                  color: palette.accent,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Informational Dialog for Non-Configured Links ---
  void _showNotConfiguredDialog({
    required BuildContext context,
    required String title,
    required String message,
    required IconData icon,
    required Locale locale,
  }) {
    final palette = context.samanColors;
    final dialogBg = palette.isDark ? const Color(0xFF151518) : palette.surface;
    final dialogBorder =
        palette.isDark ? const Color(0x14FFFFFF) : palette.border;
    final iconBoxBg =
        palette.isDark ? const Color(0x14FFFFFF) : palette.surfaceElevated;
    final mutedColor =
        palette.isDark ? const Color(0xFF8E8E93) : palette.textSecondary;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: dialogBorder, width: 1),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBoxBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(icon, color: mutedColor, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: mutedColor,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                AppTranslations.text('close', locale),
                style: TextStyle(
                  color: palette.isDark ? Colors.white : palette.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

