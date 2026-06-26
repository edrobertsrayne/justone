import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'messaging_service.dart';
import 'registration_controller.dart';

/// Registers the FCM token for the signed-in session: once on mount (if already
/// granted) and on every token rotation. Sibling of [DailyResetScope]. It never
/// requests permission — that is user-initiated (onboarding / Settings).
class NotificationScope extends ConsumerStatefulWidget {
  const NotificationScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationScope> createState() => _NotificationScopeState();
}

class _NotificationScopeState extends ConsumerState<NotificationScope> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(registrationControllerProvider).registerIfGranted();
    });
    _sub = ref.read(messagingServiceProvider).onTokenRefresh.listen(
          (token) => ref.read(registrationControllerProvider).saveTokenIfGranted(token),
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
