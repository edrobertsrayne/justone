import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/notifications/messaging_service.dart';
import 'package:justone/notifications/registration_controller.dart';

import '../support/fake_messaging_service.dart';

InMemoryRepository _repo() => InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 26)),
      tasks: const [],
    );

RegistrationController _ctrl(InMemoryRepository repo, FakeMessagingService fake) =>
    RegistrationController(
      repo: repo,
      messaging: fake,
      now: () => DateTime(2026, 6, 26, 8),
      platform: 'android',
    );

void main() {
  test('registerIfGranted upserts the token when already granted', () async {
    final repo = _repo();
    final fake = FakeMessagingService(status: NotifPermission.granted, token: 'tok-1');
    addTearDown(fake.dispose);
    await _ctrl(repo, fake).registerIfGranted();
    expect(repo.deviceUpserts.single.token, 'tok-1');
  });

  test('registerIfGranted does nothing when not granted', () async {
    final repo = _repo();
    final fake = FakeMessagingService(status: NotifPermission.denied);
    addTearDown(fake.dispose);
    await _ctrl(repo, fake).registerIfGranted();
    expect(repo.deviceUpserts, isEmpty);
  });

  test('requestAndRegister grant path prompts, saves token, returns granted', () async {
    final repo = _repo();
    final fake = FakeMessagingService(status: NotifPermission.denied, grantOnRequest: true, token: 'tok-9');
    addTearDown(fake.dispose);
    final result = await _ctrl(repo, fake).requestAndRegister();
    expect(result, NotifPermission.granted);
    expect(fake.requestCount, 1);
    expect(repo.deviceUpserts.single.token, 'tok-9');
  });

  test('requestAndRegister deny path writes nothing', () async {
    final repo = _repo();
    final fake = FakeMessagingService(status: NotifPermission.notDetermined, grantOnRequest: false);
    addTearDown(fake.dispose);
    expect(await _ctrl(repo, fake).requestAndRegister(), NotifPermission.denied);
    expect(repo.deviceUpserts, isEmpty);
  });

  test('saveToken upserts directly (used by token refresh)', () async {
    final repo = _repo();
    final fake = FakeMessagingService();
    addTearDown(fake.dispose);
    await _ctrl(repo, fake).saveToken('tok-refreshed');
    expect(repo.deviceUpserts.single.token, 'tok-refreshed');
  });
}
