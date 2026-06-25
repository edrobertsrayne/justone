import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/task.dart';
import '../theme/palette.dart';

// Hero-internal shades — not reusable tokens, so they live here.
const Color _heroOverline = Color(0xFF93A58F);
const Color _heroSubtext = Color(0xFFEEF2E8);
const Color _backChevron = Color(0xFF6F6A60);
const Color _statLabel = Color(0xFFA8A193);

/// The stats screen — the app's one deliberately loud surface (HANDOFF §1, §7).
/// Static by design; an entrance animation is a deferred follow-up.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).value;
    final tasks = ref.watch(tasksProvider).value;
    if (user == null || tasks == null) {
      return const ColoredBox(color: Palette.paper, child: SizedBox.expand());
    }

    final poolCount = tasks
        .where((t) => t.status != TaskStatus.archived && t.status != TaskStatus.removed)
        .length;

    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    key: const ValueKey('stats-back'),
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: const [
                          BoxShadow(color: Color(0x1A2B2824), blurRadius: 3, offset: Offset(0, 1)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text('‹',
                          style: TextStyle(
                              fontFamily: 'Nunito Sans',
                              fontWeight: FontWeight.w600,
                              fontSize: 17.7,
                              color: _backChevron)),
                    ),
                  ),
                  const Text('Your stats',
                      style: TextStyle(
                          fontFamily: 'Newsreader',
                          fontWeight: FontWeight.w600,
                          fontSize: 15.8,
                          color: Palette.ink)),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                child: Column(
                  children: [
                    _HeroCard(streak: user.streak),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                            child: _StatCard(
                                value: '${user.targetMetDays}',
                                label: 'Days at target',
                                valueColor: Palette.statsAccent)),
                        const SizedBox(width: 11),
                        Expanded(
                            child: _StatCard(
                                value: '${user.bestStreak}', label: 'Longest streak')),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Expanded(
                            child: _StatCard(
                                value: '${user.lifetimeDone}', label: 'Chores completed')),
                        const SizedBox(width: 11),
                        Expanded(
                            child: _StatCard(value: '$poolCount', label: 'In your pool')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Palette.statsHero,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 22),
      child: Column(
        children: [
          const Text('CURRENT STREAK',
              style: TextStyle(
                  fontFamily: 'Nunito Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 9.8,
                  letterSpacing: 2.16,
                  color: _heroOverline)),
          const SizedBox(height: 10),
          Text('$streak',
              style: const TextStyle(
                  fontFamily: 'Newsreader',
                  fontWeight: FontWeight.w500,
                  fontSize: 72.8,
                  height: 1,
                  color: Palette.statsGold)),
          const SizedBox(height: 2),
          const Text('days showing up',
              style: TextStyle(
                  fontFamily: 'Newsreader',
                  fontWeight: FontWeight.w500,
                  fontSize: 15.8,
                  color: _heroSubtext)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, this.valueColor = Palette.ink});

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x0D2B2824), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontFamily: 'Newsreader',
                  fontWeight: FontWeight.w500,
                  fontSize: 35.9,
                  height: 1,
                  color: valueColor)),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Nunito Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 11.1,
                  height: 1.3,
                  color: _statLabel)),
        ],
      ),
    );
  }
}
