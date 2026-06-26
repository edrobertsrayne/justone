import 'dart:async';

import 'package:justone/notifications/messaging_service.dart';

class FakeMessagingService implements MessagingService {
  FakeMessagingService({
    this.status = NotifPermission.granted,
    this.token = 'tok-1',
    this.grantOnRequest = true,
  });

  NotifPermission status;
  String? token;
  bool grantOnRequest;
  int requestCount = 0;
  final _refresh = StreamController<String>.broadcast();

  @override
  Future<NotifPermission> requestPermission() async {
    requestCount++;
    status = grantOnRequest ? NotifPermission.granted : NotifPermission.denied;
    return status;
  }

  @override
  Future<NotifPermission> permissionStatus() async => status;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  void emitRefresh(String t) => _refresh.add(t);
  void dispose() => _refresh.close();
}
