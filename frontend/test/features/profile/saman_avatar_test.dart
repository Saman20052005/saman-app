import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/widgets/saman_avatar.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';

void main() {
  group('SamanAvatar Widget Tests', () {
    test('Initials generation logic', () {
      expect(SamanAvatar.getInitials(''), 'SA');
      expect(SamanAvatar.getInitials('   '), 'SA');
      expect(SamanAvatar.getInitials('Saman'), 'SA');
      expect(SamanAvatar.getInitials('John Doe'), 'JD');
      expect(SamanAvatar.getInitials('Nguyen Van An'), 'NA');
      expect(SamanAvatar.getInitials('A'), 'A');
    });

    testWidgets('Renders initials inside container when avatarUrl is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SamanAvatar(
              name: 'Saman Athlete',
              avatarUrl: null,
              size: 52,
            ),
          ),
        ),
      );

      expect(find.text('SA'), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxWidth, 52);
      expect(container.constraints?.maxHeight, 52);
    });

    testWidgets('Renders initials when avatarUrl is empty whitespace',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SamanAvatar(
              name: 'John Doe',
              avatarUrl: '   ',
              size: 60,
            ),
          ),
        ),
      );

      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('Renders CachedNetworkImage with initials placeholder on network image',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SamanAvatar(
              name: 'Alex Hunter',
              avatarUrl: 'https://example.com/broken_avatar.jpg',
              size: 52,
            ),
          ),
        ),
      );

      expect(find.text('AH'), findsOneWidget);
    });
  });

  group('ProfileSnapshotModel Avatar Serialization Tests', () {
    test('Serialization to and from JSON preserves avatar fields', () {
      final json = {
        'user_id': 'u123',
        'email': 'athlete@example.com',
        'full_name': 'Athlete Name',
        'avatar': 'https://res.cloudinary.com/saman/avatar.jpg',
        'avatar_source': 'custom',
        'can_use_google_avatar': true,
        'profile': {
          'age': 25,
          'gender': 'male',
          'height': 175.0,
          'weight': 70.0,
          'activity_level': 'medium',
          'goal': 'maintain_weight',
        },
        'health_stats': {
          'daily_calories': 2200,
          'target_protein': 140,
          'target_carbs': 250,
          'target_fat': 65,
          'water_target_ml': 2500,
        },
      };

      final model = ProfileSnapshotModel.fromJson(json);
      expect(model.userId, 'u123');
      expect(model.avatar, 'https://res.cloudinary.com/saman/avatar.jpg');
      expect(model.avatarSource, 'custom');
      expect(model.canUseGoogleAvatar, true);

      final outJson = model.toJson();
      expect(outJson['avatar'], 'https://res.cloudinary.com/saman/avatar.jpg');
      expect(outJson['avatar_source'], 'custom');
      expect(outJson['can_use_google_avatar'], true);
    });

    test('Defaults avatarSource to none and canUseGoogleAvatar to false when omitted', () {
      final json = {
        'user_id': 'u456',
        'email': 'athlete2@example.com',
        'profile': {
          'age': 30,
          'gender': 'female',
          'height': 165.0,
          'weight': 55.0,
          'activity_level': 'high',
          'goal': 'gain_muscle',
        },
      };

      final model = ProfileSnapshotModel.fromJson(json);
      expect(model.avatar, isNull);
      expect(model.avatarSource, 'none');
      expect(model.canUseGoogleAvatar, false);
    });

    test('copyWith properly updates avatar and source', () {
      final model = ProfileSnapshotModel(
        userId: 'u789',
        profile: ProfileEntity.empty(),
        avatar: 'https://lh3.googleusercontent.com/pic',
        avatarSource: 'google',
        canUseGoogleAvatar: true,
      );

      final updated = model.copyWith(
        avatar: 'https://res.cloudinary.com/saman/new.jpg',
        avatarSource: 'custom',
      );

      expect(updated.avatar, 'https://res.cloudinary.com/saman/new.jpg');
      expect(updated.avatarSource, 'custom');
      expect(updated.canUseGoogleAvatar, true);
    });
  });
}

