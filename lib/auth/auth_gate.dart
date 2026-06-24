import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/daily_reset_scope.dart';
import '../theme/palette.dart';
import '../ui/home_router.dart';
import '../ui/sign_in_screen.dart';
import 'auth_providers.dart';
import 'bootstrap.dart';

/// Top-level gate: signed-out -> SignInScreen; signed-in -> bootstrap -> app.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authProvider).when(
          loading: () => const _Splash(),
          error: (_, __) => const SignInScreen(),
          data: (user) {
            if (user == null) return const SignInScreen();
            return ref.watch(bootstrapProvider).when(
                  loading: () => const _Splash(),
                  // Bootstrap only fails offline on a brand-new account; network is
                  // present right after Google sign-in (spec §C). Show the splash;
                  // it retries when the provider is re-read.
                  error: (_, __) => const _Splash(),
                  data: (_) => const DailyResetScope(child: HomeRouter()),
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
