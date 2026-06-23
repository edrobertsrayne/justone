import 'package:flutter/material.dart';

import '../domain/user_state.dart';
import '../theme/palette.dart';

/// Daily target reached — the one moment the streak number surfaces in the loop.
class TargetHitScreen extends StatelessWidget {
  const TargetHitScreen({super.key, required this.user, required this.onKeepGoing});

  final UserState user;
  final VoidCallback onKeepGoing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  user.target,
                  (_) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4.5),
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Daily target met',
                  style: TextStyle(
                      fontFamily: 'Newsreader', fontWeight: FontWeight.w500, fontSize: 28.4, color: Palette.accent)),
              const SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Stat(value: '${user.streak}', label: 'Day streak', sub: 'showed up', color: Palette.accent),
                      const VerticalDivider(width: 1, color: Color(0xFFEFE9DE), indent: 16, endIndent: 16),
                      _Stat(value: '${user.targetMetDays}', label: 'On target', sub: 'hit full goal', color: Palette.ink),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 210,
                child: Text("You've done enough for today.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Nunito Sans', fontSize: 14, height: 1.55, color: Palette.muted)),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onKeepGoing,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDDD6C9), width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('Keep going!',
                      style: TextStyle(
                          fontFamily: 'Nunito Sans', fontWeight: FontWeight.w700, fontSize: 12.4, color: Color(0xFF6F6A60))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.sub, required this.color});

  final String value;
  final String label;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontFamily: 'Newsreader', fontWeight: FontWeight.w500, fontSize: 40.4, color: color)),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Nunito Sans', fontWeight: FontWeight.w700, fontSize: 8.7, letterSpacing: 1.0, color: Color(0xFFA8A193))),
          const SizedBox(height: 3),
          Text(sub, style: const TextStyle(fontFamily: 'Nunito Sans', fontSize: 11.1, color: Color(0xFFBDB7AB))),
        ],
      ),
    );
  }
}
