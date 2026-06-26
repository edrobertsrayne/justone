import 'package:flutter_test/flutter_test.dart';
import 'package:justone/notifications/messaging_service.dart';

import '../support/fake_messaging_service.dart';

void main() {
  test('requestPermission flips a denied fake to granted and counts calls', () async {
    final fake = FakeMessagingService(status: NotifPermission.denied, grantOnRequest: true);
    addTearDown(fake.dispose);
    expect(await fake.permissionStatus(), NotifPermission.denied);
    expect(await fake.requestPermission(), NotifPermission.granted);
    expect(fake.requestCount, 1);
  });

  test('a denying fake stays denied after a request', () async {
    final fake = FakeMessagingService(status: NotifPermission.notDetermined, grantOnRequest: false);
    addTearDown(fake.dispose);
    expect(await fake.requestPermission(), NotifPermission.denied);
  });
}
