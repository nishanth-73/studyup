import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('the first account owns local data until the user erases it', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(localAccountDataAccessProvider('account-a').future),
      isTrue,
    );
    expect(
      await container.read(localAccountDataAccessProvider('account-a').future),
      isTrue,
    );
    expect(
      await container.read(localAccountDataAccessProvider('account-b').future),
      isFalse,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        localDataOwnerPreferenceKey,
      ),
      'account-a',
    );

    await clearPostSignInLink();
    expect(
      await container.read(localAccountDataAccessProvider('account-a').future),
      isTrue,
    );
    expect(
      await container.read(localAccountDataAccessProvider('account-b').future),
      isFalse,
    );
  });

  test(
    'an existing linked account is used as the owner during migration',
    () async {
      SharedPreferences.setMockInitialValues({
        'studyup.linkedUserId.v1': 'account-a',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(
          localAccountDataAccessProvider('account-b').future,
        ),
        isFalse,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          localDataOwnerPreferenceKey,
        ),
        isNull,
      );
      expect(
        await container.read(
          localAccountDataAccessProvider('account-a').future,
        ),
        isTrue,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          localDataOwnerPreferenceKey,
        ),
        'account-a',
      );
    },
  );
}
