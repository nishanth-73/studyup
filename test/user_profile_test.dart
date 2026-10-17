import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/avatar/data/user_profile.dart';
import 'package:studyup/features/avatar/presentation/avatar_widgets.dart';
import 'package:studyup/features/avatar/presentation/user_profile_controller.dart';

void main() {
  group('UserProfile', () {
    test('JSON round-trip preserves name and completion', () {
      const profile = UserProfile(displayName: 'Alex', blobName: 'alex');
      final restored = UserProfile.fromJson(
        Map<String, Object?>.from(profile.toJson()),
      );
      expect(restored.displayName, 'Alex');
      expect(restored.blobName, 'alex');
      expect(restored.onboardingComplete, isTrue);
    });

    test('legacy Blob settings survive a profile read and write', () {
      final restored = UserProfile.fromJson({
        'ownerId': 'local',
        'displayName': 'Alex',
        'blobName': 'alex',
        'avatarId': 'avatar5',
        'blobShape': 0.888,
        'blobShapeId': 'cloud',
        'onboardingComplete': true,
      });
      expect(restored.displayName, 'Alex');
      expect(restored.blobName, 'alex');
      expect(restored.avatarId, 'avatar5');
      expect(restored.blobShape, 0.888);
      expect(restored.blobShapeId, 'cloud');
      expect(restored.onboardingComplete, isTrue);
      expect(restored.toJson()['avatarId'], 'avatar5');
      expect(restored.toJson()['blobShape'], 0.888);
      expect(restored.toJson()['blobShapeId'], 'cloud');
    });

    test('Blob variant survives a JSON round-trip', () {
      const profile = UserProfile(
        displayName: 'Alex',
        blobName: 'alex',
        blobVariant: 3,
      );
      final restored = UserProfile.fromJson(
        Map<String, Object?>.from(profile.toJson()),
      );
      expect(restored.blobVariant, 3);
    });
  });

  group('UserProfileController persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts with no profile (onboarding state, never random)', () async {
      final controller = UserProfileController();
      await _waitForSettled(controller);
      expect(controller.state.valueOrNull, isNull);
      controller.dispose();
    });

    test('Alex survives a full reload unchanged', () async {
      final first = UserProfileController();
      await _waitForSettled(first);
      await first.completeOnboarding(displayName: 'Alex');
      first.dispose();

      final restored = UserProfileController();
      await _waitForSettled(restored);
      final profile = restored.state.valueOrNull!;
      expect(profile.displayName, 'Alex');
      expect(profile.blobName, 'alex');
      expect(profile.onboardingComplete, isTrue);
      restored.dispose();
    });

    test(
      'renaming and changing Blob color preserve profile identity',
      () async {
        final controller = UserProfileController();
        await _waitForSettled(controller);
        await controller.completeOnboarding(displayName: 'Alex');
        await controller.updateDisplayName('Alexander');
        await controller.updateBlobVariant(2);
        final profile = controller.state.valueOrNull!;
        expect(profile.displayName, 'Alexander');
        expect(profile.blobName, 'alex');
        expect(profile.blobVariant, 2);
        controller.dispose();
      },
    );

    test(
      'changing Blob preserves older saved settings across reload',
      () async {
        SharedPreferences.setMockInitialValues({
          'studyup.userProfile.v1': '{"ownerId":"local","displayName":"Alex","blobName":"alex","onboardingComplete":true,"avatarId":"avatar4","blobShape":0.888,"blobShapeId":"cloud","slidesSeen":true,"setupComplete":true,"demoSignedIn":true,"demoEmail":"alex@example.com"}',
        });
        final controller = UserProfileController();
        await _waitForSettled(controller);
        await controller.updateBlobVariant(3);
        controller.dispose();

        final restored = UserProfileController();
        await _waitForSettled(restored);
        final profile = restored.state.valueOrNull!;
        expect(profile.blobVariant, 3);
        expect(profile.avatarId, 'avatar4');
        expect(profile.blobShape, 0.888);
        expect(profile.blobShapeId, 'cloud');
        expect(profile.demoEmail, 'alex@example.com');
        restored.dispose();
      },
    );

    test('blank names are rejected', () async {
      final controller = UserProfileController();
      await _waitForSettled(controller);
      await expectLater(
        controller.completeOnboarding(displayName: '  '),
        throwsArgumentError,
      );
      controller.dispose();
    });

    test('avatar portrait changes persist across reload', () async {
      final controller = UserProfileController();
      await _waitForSettled(controller);
      await controller.completeOnboarding(displayName: 'Alex');
      await controller.updateAvatarId('avatar5');
      expect(controller.state.valueOrNull!.avatarId, 'avatar5');
      controller.dispose();

      final restored = UserProfileController();
      await _waitForSettled(restored);
      expect(restored.state.valueOrNull!.avatarId, 'avatar5');
      restored.dispose();
    });

    test('unknown avatar ids are rejected', () async {
      final controller = UserProfileController();
      await _waitForSettled(controller);
      await controller.completeOnboarding(displayName: 'Alex');
      await expectLater(
        controller.updateAvatarId('avatar99'),
        throwsArgumentError,
      );
      expect(controller.state.valueOrNull!.avatarId, 'avatar1');
      controller.dispose();
    });

    test('avatar assets fall back to the default portrait', () {
      expect(avatarAssetForId('avatar3'), 'assets/images/avatars/avatar3.png');
      expect(avatarAssetForId('nope'), 'assets/images/avatars/avatar1.png');
      expect(avatarAssetForId(''), 'assets/images/avatars/avatar1.png');
    });
  });
}

Future<void> _waitForSettled(UserProfileController controller) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (!controller.state.isLoading) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Profile did not finish loading.');
}
