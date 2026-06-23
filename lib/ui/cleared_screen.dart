import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// "You're caught up" — tasks remain but none are due. Distinct from emptyPool.
/// Terminal for the day: the only exit is reviewing the pool (no re-serve).
class ClearedScreen extends StatelessWidget {
  const ClearedScreen({super.key, required this.onReviewPool});

  final VoidCallback onReviewPool;

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
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "You're on top of\nthings",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Newsreader', fontWeight: FontWeight.w500, fontSize: 28.4, color: Palette.ink),
              ),
              const SizedBox(height: 14),
              const SizedBox(
                width: 200,
                child: Text(
                  'Nothing left in the pool. Enjoy the quiet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Nunito Sans', fontSize: 15.8, height: 1.55, color: Palette.muted),
                ),
              ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: onReviewPool,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDDD6C9), width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Review pool',
                    style: TextStyle(
                        fontFamily: 'Nunito Sans',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.4,
                        color: Color(0xFF6F6A60)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
