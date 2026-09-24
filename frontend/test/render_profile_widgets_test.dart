import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/screens/profile/widgets/profile_widgets.dart';

void main() {
  const viewports = [
    Size(320, 568),
    Size(375, 812),
    Size(430, 932),
  ];

  const textScales = [1.0, 1.3, 2.0];

  for (final viewport in viewports) {
    for (final scale in textScales) {
      group('Responsive Matrix: ${viewport.width.toInt()}x${viewport.height.toInt()} @ scale $scale', () {
        testWidgets('English content with full metrics rendering without overflow', (tester) async {
          tester.view.physicalSize = viewport * tester.view.devicePixelRatio;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: viewport,
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        ProfileHeader(
                          title: 'Profile',
                          subtitle: 'Your health, progress & account',
                          onSettingsTap: () {},
                        ),
                        PersonalIdentityCard(
                          userName: 'Alexander Supertramp Longname',
                          userEmail: 'alexander.supertramp.longemail@domain.com',
                          planLabel: 'Premium Member Plan',
                          memberSince: 'Member since January 2024',
                          onEditProfileTap: () {},
                        ),
                        ProgressSnapshotCard(
                          workoutsCount: 999999,
                          streakDays: 365,
                          adherencePercent: 100,
                          onViewProgressTap: () {},
                        ),
                        SamanPlusCard(
                          onExploreTap: () {},
                        ),
                        ProfileSectionGroup(
                          title: 'ACCOUNT PREFERENCES',
                          children: [
                            ProfileNavRow(
                              title: 'Personal Health Data',
                              value: 'Updated 2d ago',
                              onTap: () {},
                            ),
                            ProfileNavRow(
                              title: 'Privacy & Security Controls',
                              value: 'Private',
                              onTap: () {},
                            ),
                          ],
                        ),
                        LogoutRow(
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });

        testWidgets('Long Vietnamese content & zero/null metrics rendering without overflow', (tester) async {
          tester.view.physicalSize = viewport * tester.view.devicePixelRatio;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: viewport,
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        ProfileHeader(
                          title: 'Hồ sơ cá nhân',
                          subtitle: 'Sức khỏe, tiến trình & tài khoản của bạn',
                          onSettingsTap: () {},
                          settingsLabel: 'Cài đặt',
                        ),
                        PersonalIdentityCard(
                          userName: 'Nguyễn Trần Quang Trường Giang',
                          userEmail: 'nguyentranquangtruonggiang@sanbox.vn',
                          planLabel: 'Gói Miễn Phí',
                          memberSince: 'Thành viên từ năm 2026',
                          onEditProfileTap: () {},
                          editProfileLabel: 'Chỉnh sửa hồ sơ',
                        ),
                        ProgressSnapshotCard(
                          workoutsCount: 0,
                          streakDays: 0,
                          adherencePercent: 0,
                          onViewProgressTap: () {},
                          title: 'TIẾN TRÌNH CỦA BẠN',
                          workoutsLabel: 'Buổi tập',
                          streakLabel: 'Chuỗi hiện tại',
                          adherenceLabel: 'Mức độ tuân thủ',
                          viewProgressLabel: 'Xem chi tiết tiến trình',
                        ),
                        SamanPlusCard(
                          onExploreTap: () {},
                          badgeLabel: 'SAMAN+ NÂNG CAO',
                          title: 'Khám phá thêm tính năng nâng cao cùng Saman+',
                          description: 'Lộ trình cá nhân hóa linh hoạt, phân tích chuyên sâu.',
                          benefits: 'Báo cáo chi tiết · Xu hướng cơ thể · Trợ lý AI',
                          exploreLabel: 'Khám phá Saman+',
                        ),
                        ProfileSectionGroup(
                          title: 'MỤC TIÊU & TÙY CHỌN TÀI KHOẢN',
                          children: [
                            ProfileNavRow(
                              title: 'Cài đặt thông báo & nhắc nhở',
                              value: 'Đã bật',
                              onTap: () {},
                            ),
                            ProfileNavRow(
                              title: 'Chính sách bảo mật dữ liệu',
                              onTap: () {},
                            ),
                          ],
                        ),
                        LogoutRow(
                          onTap: () {},
                          label: 'Đăng xuất tài khoản',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });

        testWidgets('Missing optional content (null metrics, null plan, null callbacks) without overflow', (tester) async {
          tester.view.physicalSize = viewport * tester.view.devicePixelRatio;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: viewport,
                  textScaler: TextScaler.linear(scale),
                ),
                child: const Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        ProfileHeader(),
                        PersonalIdentityCard(
                          userName: '',
                          userEmail: '',
                        ),
                        ProgressSnapshotCard(),
                        SamanPlusCard(
                          comingSoonLabel: 'Tính năng sắp ra mắt',
                        ),
                        ProfileSectionGroup(
                          children: [
                            ProfileNavRow(
                              title: 'Phiên bản ứng dụng',
                              value: '1.0.0',
                            ),
                          ],
                        ),
                        LogoutRow(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      });
    }
  }

  group('Theme Safety Tests', () {
    testWidgets('Renders properly in Light Theme without crashing or losing content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ProfileHeader(onSettingsTap: () {}),
                  PersonalIdentityCard(
                    userName: 'John Doe',
                    userEmail: 'john@example.com',
                    planLabel: 'Free Plan',
                    memberSince: 'Member since 2025',
                    onEditProfileTap: () {},
                  ),
                  ProgressSnapshotCard(
                    workoutsCount: 15,
                    streakDays: 5,
                    adherencePercent: 90,
                    onViewProgressTap: () {},
                  ),
                  SamanPlusCard(onExploreTap: () {}),
                  ProfileSectionGroup(
                    title: 'PREFERENCES',
                    children: [
                      ProfileNavRow(title: 'Theme', value: 'Light', onTap: () {}),
                    ],
                  ),
                  LogoutRow(onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Explore Saman+'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('Renders properly in Dark Theme without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ProfileHeader(),
                  PersonalIdentityCard(
                    userName: 'John Doe',
                    userEmail: 'john@example.com',
                  ),
                  ProgressSnapshotCard(
                    workoutsCount: 15,
                    streakDays: 5,
                    adherencePercent: 90,
                  ),
                  SamanPlusCard(),
                  ProfileSectionGroup(
                    title: 'PREFERENCES',
                    children: [
                      ProfileNavRow(title: 'Theme', value: 'Dark'),
                    ],
                  ),
                  LogoutRow(),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
