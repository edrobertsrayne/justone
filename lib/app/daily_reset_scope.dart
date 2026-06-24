import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/transitions.dart';
import '../domain/urgency.dart' show daysBetweenLocalDates;
import 'providers.dart';

/// Runs the client-authoritative daily reset (D7) on cold start and every
/// resume-to-foreground (D22). Idempotent: a no-op when the local day is unchanged.
class DailyResetScope extends ConsumerStatefulWidget {
  const DailyResetScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DailyResetScope> createState() => _DailyResetScopeState();
}

class _DailyResetScopeState extends ConsumerState<DailyResetScope> with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-check whenever the user or task stream first delivers (or updates).
    ref.listenManual(userProvider, (_, __) => _maybeReset());
    ref.listenManual(tasksProvider, (_, __) => _maybeReset());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeReset());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeReset();
  }

  Future<void> _maybeReset() async {
    if (_busy) return;
    final user = ref.read(userProvider).value;
    final tasks = ref.read(tasksProvider).value;
    if (user == null || tasks == null) return;
    final now = ref.read(nowProvider)();
    if (daysBetweenLocalDates(user.lastActiveDate, now) == 0) return;
    _busy = true;
    try {
      final dateNow = DateTime(now.year, now.month, now.day);
      await ref.read(repositoryProvider).commit(dailyReset(user, tasks, dateNow));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
