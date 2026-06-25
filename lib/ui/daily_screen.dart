import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/daily_controller.dart';
import '../app/providers.dart';
import '../domain/task.dart';
import '../domain/urgency.dart';
import '../domain/user_state.dart';
import '../theme/palette.dart';
import 'add_sheet.dart';
import 'manage_screen.dart';
import 'placeholder_screen.dart';
import 'swipe_card.dart';

class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key, required this.user, required this.task});

  final UserState user;
  final Task task;

  void _open(BuildContext context, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceholderScreen(title: title)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(dailyControllerProvider);
    final now = ref.watch(nowProvider)();
    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _ChromeButton(
                          icon: Icons.menu,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageScreen()))),
                      const Text('TODAY',
                          style: TextStyle(
                              fontFamily: 'Nunito Sans',
                              fontWeight: FontWeight.w700,
                              fontSize: 9.8,
                              letterSpacing: 1.96,
                              color: Color(0xFFC2BCAE))),
                      _ChromeButton(icon: Icons.bar_chart, onTap: () => _open(context, 'Stats')),
                    ],
                  ),
                ),
                Expanded(
                  child: SwipeCard(
                    task: task,
                    urgency: urgencyOf(task, now),
                    canSkip: user.rerolls > 0,
                    onComplete: () => controller.complete(user, task),
                    onSkip: () => controller.skip(user, task),
                    onSkipDenied: controller.skipDenied,
                    onRemove: () => controller.remove(user, task),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 22,
              bottom: 30,
              child: GestureDetector(
                key: const ValueKey('daily-fab'),
                onTap: () => showAddSheet(context, ref),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(19)),
                  child: const Icon(Icons.add, color: Palette.paper),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, size: 18, color: const Color(0xFF8A847A)),
      ),
    );
  }
}
