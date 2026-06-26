import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/repository.dart';
import 'messaging_service.dart';

/// Owns the FCM token lifecycle: register on grant / app-open, and on rotation.
class RegistrationController {
  RegistrationController({
    required Repository repo,
    required MessagingService messaging,
    required Clock now,
    required String platform,
  })  : _repo = repo,
        _messaging = messaging,
        _now = now,
        _platform = platform;

  final Repository _repo;
  final MessagingService _messaging;
  final Clock _now;
  final String _platform;

  /// Prompt for permission; on grant, save the current token. Returns the status.
  Future<NotifPermission> requestAndRegister() async {
    final status = await _messaging.requestPermission();
    if (status == NotifPermission.granted) await _saveCurrentToken();
    return status;
  }

  /// App-open path: refresh the device doc only if permission is already granted.
  Future<void> registerIfGranted() async {
    if (await _messaging.permissionStatus() == NotifPermission.granted) {
      await _saveCurrentToken();
    }
  }

  /// Upsert a specific token (used by the onTokenRefresh subscription).
  Future<void> saveToken(String token) =>
      _repo.upsertDevice(token: token, platform: _platform, now: _now());

  Future<void> _saveCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null) await saveToken(token);
  }
}

final registrationControllerProvider = Provider<RegistrationController>(
  (ref) => RegistrationController(
    repo: ref.watch(repositoryProvider),
    messaging: ref.watch(messagingServiceProvider),
    now: ref.watch(nowProvider),
    platform: defaultTargetPlatform.name,
  ),
);
