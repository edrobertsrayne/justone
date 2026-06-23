import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Zero tasks in the pool — distinct from `cleared` (which has tasks, none due).
class EmptyPoolScreen extends StatelessWidget {
  const EmptyPoolScreen({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0xFFE9EEE2), Palette.paper]),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDFE5D8)),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Your pool\nis empty',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Newsreader', fontWeight: FontWeight.w500, fontSize: 28.4, color: Palette.ink),
              ),
              const SizedBox(height: 14),
              const SizedBox(
                width: 210,
                child: Text(
                  'Nothing to do, and nothing hanging over you. Add a chore whenever one turns up.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Nunito Sans', fontSize: 15.8, height: 1.55, color: Palette.muted),
                ),
              ),
              const SizedBox(height: 30),
              _Pill(label: 'Add a chore', filled: true, onTap: onAdd),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared CTA pill: filled (ink) or outline. Reused by the rest screens.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        decoration: BoxDecoration(
          color: filled ? Palette.ink : null,
          border: filled ? null : Border.all(color: const Color(0xFFDDD6C9), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Nunito Sans',
            fontWeight: FontWeight.w700,
            fontSize: 12.4,
            color: filled ? Palette.paper : const Color(0xFF6F6A60),
          ),
        ),
      ),
    );
  }
}
