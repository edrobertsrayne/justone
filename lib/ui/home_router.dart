import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/daily_controller.dart';
import '../app/providers.dart';
import '../domain/routing.dart';
import '../domain/selection.dart';
import '../theme/palette.dart';
import 'add_sheet.dart';
import 'cleared_screen.dart';
import 'daily_screen.dart';
import 'empty_pool_screen.dart';
import 'manage_screen.dart';
import 'onboarding_flow.dart';
import 'target_hit_screen.dart';

/// Derives the current screen purely from routeHome and renders it.
class HomeRouter extends ConsumerWidget {
  const HomeRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);
    final tasksAsync = ref.watch(tasksProvider);
    final now = ref.watch(nowProvider)();

    final user = userAsync.value;
    final tasks = tasksAsync.value;
    if (user == null || tasks == null) {
      return const ColoredBox(color: Palette.paper, child: SizedBox.expand());
    }

    final screen = routeHome(user, tasks, now);
    final child = switch (screen) {
      AppScreen.onboardTarget => const OnboardingFlow(),
      AppScreen.daily => DailyScreen(user: user, task: selectTask(tasks, now)!),
      AppScreen.cleared => ClearedScreen(
          onReviewPool: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageScreen()))),
      AppScreen.emptyPool => EmptyPoolScreen(onAdd: () => showAddSheet(context, ref)),
      AppScreen.targetHit =>
        TargetHitScreen(user: user, onKeepGoing: () => ref.read(dailyControllerProvider).keepGoing(user)),
      // welcome/add/manage/settings/stats are not reachable from the
      // Phase-2 home loop (auth + those screens arrive later).
      _ => const ColoredBox(color: Palette.paper, child: SizedBox.expand()),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child);
  }
}
