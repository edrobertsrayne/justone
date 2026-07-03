import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/daily_reset_scope.dart';
import '../app/providers.dart';
import '../notifications/notification_scope.dart';
import '../theme/palette.dart';
import '../ui/home_router.dart';
import '../ui/welcome_screen.dart';
import 'auth_providers.dart';
import 'bootstrap.dart';

/// Top-level gate: signed-out -> WelcomeScreen; signed-in -> bootstrap -> app.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (prev, next) {
      // Screens like Manage/Settings are pushed onto the root Navigator, which
      // sits *above* this gate. Swapping our own child to WelcomeScreen doesn't
      // remove them, so on a sign-out transition we pop back to the gate — else
      // the user is stranded on a pushed screen even though Firebase signed out.
      if (prev?.value != null && next.value == null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      // The uid just changed, so repositoryProvider and its user/tasks streams
      // are stale. They aren't autoDispose (controllers keep them alive across a
      // sign-out), so their old elements linger; when the signed-in subtree next
      // mounts it force-flushes the dirty chain *during build*, and Riverpod
      // notifying the lingering listeners then calls setState() during build and
      // throws. We reset the chain here instead — in a listener, i.e. outside the
      // build phase — and eagerly read it back so the rebuild (and the listener
      // notifications it triggers) happen now, not during the subtree's build.
      // A plain invalidate isn't enough: the rebuild is lazy and would still land
      // during build. See the re-login test in auth_gate_test.dart.
      if (prev?.value?.uid != next.value?.uid) {
        ref.invalidate(repositoryProvider);
        ref.read(repositoryProvider);
      }
    });
    return ref.watch(authProvider).when(
          loading: () => const _Splash(),
          error: (_, __) => const WelcomeScreen(),
          data: (user) {
            if (user == null) return const WelcomeScreen();
            return ref.watch(bootstrapProvider).when(
                  loading: () => const _Splash(),
                  // Bootstrap only fails offline on a brand-new account; network is
                  // present right after Google sign-in (spec §C). Show the splash;
                  // it retries when the provider is re-read.
                  error: (_, __) => const _Splash(),
                  data: (_) => const DailyResetScope(
                    child: NotificationScope(child: HomeRouter()),
                  ),
                );
          },
        );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Palette.paper, child: SizedBox.expand());
}
