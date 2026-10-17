import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/deeplink/invite_links.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';

/// Token handoff contract across the sign-in flow:
/// - stash saves the token; peek reads it WITHOUT consuming;
/// - take is the single consumer (used once by the invite screen);
/// - pendingInviteProvider reads the stash but never replays a token that
///   was already consumed in the same process (autoDispose).
const _tokenA = 'aa11bb22cc33dd44ee55ff6600112233445566778899aabbccddeeff00112233';
const _tokenB = 'ff11ee22dd33cc44bb55aa6600112233445566778899aabbccddeeff00112233';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('stash → peek (non-consuming) → take consumes exactly once', () async {
    await InviteLinks.stashPending(_tokenA);
    expect(await InviteLinks.peekPending(), _tokenA);
    // Peeking must not consume: routing decisions can repeat safely.
    expect(await InviteLinks.peekPending(), _tokenA);
    expect(await InviteLinks.takePending(), _tokenA);
    expect(await InviteLinks.takePending(), isNull);
    expect(await InviteLinks.peekPending(), isNull);
  });

  test('a newer stash replaces the previous pending token', () async {
    await InviteLinks.stashPending(_tokenA);
    await InviteLinks.stashPending(_tokenB);
    expect(await InviteLinks.peekPending(), _tokenB);
    expect(await InviteLinks.takePending(), _tokenB);
  });

  test('pendingInviteProvider never replays a consumed token', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await InviteLinks.stashPending(_tokenA);

    final sub = container.listen(pendingInviteProvider, (_, _) {});
    expect(await container.read(pendingInviteProvider.future), _tokenA);

    // The invite screen takes the token over during the same session.
    expect(await InviteLinks.takePending(), _tokenA);

    // The startup gate unmounts → autoDispose drops the cached value, so
    // a later in-process read can only see the (now empty) stash.
    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await container.read(pendingInviteProvider.future), isNull);
  });
}
