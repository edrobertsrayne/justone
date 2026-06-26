import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime notification permission state, mapped off the platform's value.
enum NotifPermission { granted, denied, notDetermined }

/// The notification boundary: wraps `firebase_messaging`, which cannot run under
/// `flutter test`. Faked in tests (mirrors the AuthService seam).
abstract class MessagingService {
  /// Show the OS permission prompt; returns the resulting status.
  Future<NotifPermission> requestPermission();

  /// Current permission without prompting.
  Future<NotifPermission> permissionStatus();

  /// Current FCM registration token (null if unavailable).
  Future<String?> getToken();

  /// Fires when the token rotates.
  Stream<String> get onTokenRefresh;
}

class FirebaseMessagingService implements MessagingService {
  FirebaseMessagingService(this._fm);
  final FirebaseMessaging _fm;

  NotifPermission _map(AuthorizationStatus s) => switch (s) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => NotifPermission.granted,
        AuthorizationStatus.denied => NotifPermission.denied,
        _ => NotifPermission.notDetermined,
      };

  @override
  Future<NotifPermission> requestPermission() async =>
      _map((await _fm.requestPermission()).authorizationStatus);

  @override
  Future<NotifPermission> permissionStatus() async =>
      _map((await _fm.getNotificationSettings()).authorizationStatus);

  @override
  Future<String?> getToken() => _fm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;
}

final messagingServiceProvider =
    Provider<MessagingService>((ref) => FirebaseMessagingService(FirebaseMessaging.instance));

/// Async permission status for the Settings re-enable card; invalidate after a
/// request to refresh.
final notifPermissionProvider =
    FutureProvider<NotifPermission>((ref) => ref.watch(messagingServiceProvider).permissionStatus());
