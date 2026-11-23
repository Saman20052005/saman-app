import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../config/routes.dart';
import '../journal/data/datasources/journal_fake_datasource.dart';
import '../journal/data/repositories/journal_repository_impl.dart';
import '../journal/presentation/providers/journal_providers.dart';
import 'data/datasources/community_fake_datasource.dart';
import 'data/repositories/community_repository_impl.dart';
import 'presentation/providers/community_providers.dart';
import 'presentation/tokens/saman_ig_tokens.dart';

/// Entrypoint riêng biệt phục vụ kiểm chứng giao diện tương tác và nghiệm thu runtime (JCOM-04A).
///
/// Tuân thủ nghiêm ngặt AGENTS.md:
/// - Sử dụng Fake Repository in-memory qua Dependency Injection.
/// - Danh tính mẫu tổng hợp ("Linh Nguyễn - Bản xem trước").
/// - Không đọc token/session thật, không gọi API backend live.
/// - Không sửa đổi entrypoint production (`lib/main.dart`) hoặc auth/profile gate.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final communityDatasource = CommunityFakeDatasource();
  final communityRepo = CommunityRepositoryImpl(datasource: communityDatasource);

  final journalDatasource = JournalFakeDatasource();
  final journalRepo = JournalRepositoryImpl(datasource: journalDatasource);

  runApp(
    ProviderScope(
      overrides: [
        communityFakeDatasourceProvider.overrideWithValue(communityDatasource),
        communityRepositoryProvider.overrideWithValue(communityRepo),
        journalRepositoryProvider.overrideWithValue(journalRepo),
      ],
      child: const SamanCommunityPreviewApp(),
    ),
  );
}

class SamanCommunityPreviewApp extends StatefulWidget {
  const SamanCommunityPreviewApp({super.key});

  @override
  State<SamanCommunityPreviewApp> createState() =>
      _SamanCommunityPreviewAppState();
}

class _SamanCommunityPreviewAppState extends State<SamanCommunityPreviewApp> {
  Locale _locale = const Locale('vi');

  void _toggleLocale() {
    setState(() {
      _locale = _locale.languageCode == 'vi'
          ? const Locale('en')
          : const Locale('vi');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Saman Community & Journal Runtime Preview',
      debugShowCheckedModeBanner: false,
      theme: SamanTheme.light(),
      darkTheme: SamanTheme.dark(),
      themeMode: ThemeMode.system,
      locale: _locale,
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: AppRoutes.communityFeed,
      onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(settings),
      builder: (context, child) {
        final ig = SamanIgTokens.of(context);
        return Scaffold(
          backgroundColor: ig.canvas,
          body: Column(
            children: [
              _buildTopPreviewBanner(context, ig),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopPreviewBanner(BuildContext context, SamanIgTokens ig) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ig.surfaceElevated,
        border: Border(
          bottom: BorderSide(color: ig.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ig.primaryAction,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'PREVIEW',
                style: TextStyle(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: ig.onPrimaryAction,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bản xem trước nội bộ • Dữ liệu mẫu in-memory • Không có API ghi live',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ig.caption(
                  color: ig.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              onTap: _toggleLocale,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  _locale.languageCode.toUpperCase(),
                  style: TextStyle(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ig.primaryAction,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
