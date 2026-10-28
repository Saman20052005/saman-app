import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_metadata.dart';
import '../../config/app_translations.dart';
import '../../services/unit_converter.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  static const String routeName = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(languageProvider);
    final languageMode = ref.watch(languageModeProvider);
    final unitSystem = ref.watch(unitProvider);
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
      backgroundColor: const Color(0xFF0A0A0C),
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
                      AppTranslations.text('preferences', locale),
                    ),
                    _buildCardGroup(
                      children: [
                        // Row: Language
                        _buildSettingsRow(
                          key: const Key('setting_row_language'),
                          icon: Icons.public_outlined,
                          title: 'Ngôn ngữ / Language',
                          value: currentLanguageDisplay,
                          showChevron: true,
                          onTap: () => _openLanguageSheet(context, ref, locale),
                        ),
                        _buildDivider(),
                        // Row: Units
                        _buildSettingsRow(
                          key: const Key('setting_row_units'),
                          icon: Icons.straighten_outlined,
                          title: AppTranslations.text('units', locale),
                          subtitle: unitSubtitle,
                          value: currentUnitDisplay,
                          showChevron: true,
                          onTap: () => _openUnitsSheet(context, ref, locale),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // SECTION 2: ABOUT SAMAN
                    _buildSectionHeader(
                      AppTranslations.text('about_saman', locale),
                    ),
                    _buildCardGroup(
                      children: [
                        // Row: Privacy Policy
                        _buildSettingsRow(
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
                        _buildDivider(),
                        // Row: Terms of Service
                        _buildSettingsRow(
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
                        _buildDivider(),
                        // Row: Help & Support
                        _buildSettingsRow(
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
                      AppTranslations.text('app_information', locale),
                    ),
                    _buildCardGroup(
                      children: [
                        // Row: App version (Read-only, no chevron)
                        _buildSettingsRow(
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
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF636366),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('app_settings_back_button'),
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
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
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Section Header ---
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // --- Grouped Card Container ---
  Widget _buildCardGroup({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF151518),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x14FFFFFF),
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
  Widget _buildDivider() {
    return const Divider(
      color: Color(0x0FFFFFFF),
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
    );
  }

  // --- Setting Row ---
  Widget _buildSettingsRow({
    Key? key,
    required IconData icon,
    required String title,
    String? subtitle,
    String? value,
    bool showChevron = true,
    bool isReadOnly = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: isReadOnly ? null : onTap,
        splashColor: Colors.white.withOpacity(0.04),
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
                color: const Color(0xFF8E8E93),
              ),
              const SizedBox(width: 14),

              // Title and optional subtitle + trailing value within flexible layout
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      flex: 5,
                      child: subtitle != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF8E8E93),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                letterSpacing: -0.1,
                              ),
                            ),
                    ),
                    if (value != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 4,
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isReadOnly
                                ? const Color(0xFF636366)
                                : const Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Trailing Chevron
              if (showChevron) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFF636366),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151518),
      barrierColor: Colors.black.withOpacity(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, refConsumer, _) {
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
                        color: const Color(0x33FFFFFF),
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
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Option 1: Use device language
                    _buildSheetOptionTile(
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151518),
      barrierColor: Colors.black.withOpacity(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, refConsumer, _) {
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
                        color: const Color(0x33FFFFFF),
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
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Option 1: Metric
                    _buildSheetOptionTile(
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
    Key? key,
    required String title,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        splashColor: Colors.white.withOpacity(0.04),
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
                        color: isSelected ? Colors.white : const Color(0xFFD4D4D8),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF10B981),
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
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151518),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x14FFFFFF), width: 1),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(icon, color: const Color(0xFF8E8E93), size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF8E8E93),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                AppTranslations.text('close', locale),
                style: const TextStyle(
                  color: Colors.white,
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

