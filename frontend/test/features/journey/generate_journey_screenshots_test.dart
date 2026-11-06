import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:health_ai_app/features/journey/domain/models/journey_models.dart';
import 'package:health_ai_app/features/journey/data/repositories/fake_journey_repository.dart';
import 'package:health_ai_app/features/journey/presentation/providers/journey_providers.dart';
import 'package:health_ai_app/features/journey/presentation/screens/wallet_rewards_screen.dart';

Future<void> _captureToPng(WidgetTester tester, Finder boundaryFinder, String relativePath) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  final image = await boundary.toImage(pixelRatio: 2.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  expect(byteData, isNotNull);
  final bytes = byteData!.buffer.asUint8List();
  
  final file = File(relativePath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('Saved screenshot: ${file.path} (${bytes.length} bytes)');
}

Widget _wrapScreen({
  required Widget child,
  required FakeJourneyRepository repo,
  Size size = const Size(375, 812),
}) {
  return ProviderScope(
    overrides: [
      journeyRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0D0E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          surface: Color(0xFF16171B),
        ),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 44, bottom: 34),
          devicePixelRatio: 2.0,
        ),
        child: RepaintBoundary(
          key: const ValueKey('capture_frame'),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final outDir = Directory('../design/saman-journey/evidence/screenshots').existsSync()
      ? '../design/saman-journey/evidence/screenshots'
      : 'd:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/design/saman-journey/evidence/screenshots';

  testWidgets('Screenshot 5: Wallet & Rewards Screen (20 SP, Unavailable Catalog, Disabled CTA)', (tester) async {
    final repo = FakeJourneyRepository();
    repo.balance = 20;
    repo.aiCredits = 0;
    repo.transactions = [
      const PointTransaction(
        id: 'tx_daily_reward_today',
        userId: 'test_athlete',
        amount: 20,
        type: 'daily_reward',
        description: 'Thưởng hoàn thành ngày 1',
        createdAt: '2026-10-28T08:30:00Z',
      ),
    ];

    await tester.pumpWidget(_wrapScreen(child: const WalletRewardsScreen(), repo: repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ví điểm & Lượt AI'), findsOneWidget);
    expect(find.text('Các gói đổi sắp ra mắt'), findsOneWidget);

    await _captureToPng(
      tester,
      find.byKey(const ValueKey('capture_frame')),
      '$outDir/saman_screen_3_v_i_m_i_l_t_ai_chua_kha_dung.png',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

