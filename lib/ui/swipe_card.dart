import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../domain/task.dart';
import '../theme/palette.dart';

/// The daily card. Serves one task: title + urgency halo only (no counters).
/// Drag right = Done, drag left = Skip, long-press = Remove (Task 11 wires the
/// gestures onto this shell).
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    super.key,
    required this.task,
    required this.urgency,
    required this.canSkip,
    required this.onComplete,
    required this.onSkip,
    required this.onSkipDenied,
    required this.onRemove,
  });

  final Task task;
  final double urgency;
  final bool canSkip;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final VoidCallback onSkipDenied;
  final VoidCallback onRemove;

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard> with SingleTickerProviderStateMixin {
  double _dx = 0; // current horizontal drag offset

  // Fraction of card width past which a release commits the action.
  static const double thresholdFraction = 0.25;

  late final AnimationController _spring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  double _width = 0;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    final threshold = (_width == 0 ? 200 : _width * thresholdFraction);
    if (_dx > threshold) {
      _flingOff(1, widget.onComplete);
    } else if (_dx < -threshold) {
      if (widget.canSkip) {
        _flingOff(-1, widget.onSkip);
      } else {
        _springBack();
        widget.onSkipDenied();
      }
    } else {
      _springBack();
    }
  }

  void _springBack() {
    final from = _dx;
    _spring
      ..reset()
      ..duration = const Duration(milliseconds: 250);
    final anim = Tween<double>(begin: from, end: 0)
        .animate(CurvedAnimation(parent: _spring, curve: Curves.easeOutCubic));
    void listener() => setState(() => _dx = anim.value);
    anim.addListener(listener);
    _spring.forward().whenComplete(() => anim.removeListener(listener));
  }

  void _flingOff(int dir, VoidCallback then) {
    final target = dir * (_width == 0 ? 800.0 : _width * 1.5);
    final from = _dx;
    _spring
      ..reset()
      ..duration = const Duration(milliseconds: 200);
    final anim = Tween<double>(begin: from, end: target)
        .animate(CurvedAnimation(parent: _spring, curve: Curves.easeOut));
    void listener() => setState(() => _dx = anim.value);
    anim.addListener(listener);
    _spring.forward().whenComplete(() {
      anim.removeListener(listener);
      then();
    });
  }

  double get _doneOpacity => _dx > 0 ? (_dx / 160).clamp(0.0, 1.0) : 0.0;
  double get _skipOpacity => _dx < 0 ? (-_dx / 160).clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context) {
    final u = widget.urgency.clamp(0.0, 1.0);
    final sz = 340 + u * 160;
    // Gaussian sigma scaled from the design spec: blur(62px) on a 300px ellipse.
    final haloSigma = sz * (62 / 300);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return Stack(
          children: [
            // Halo: solid ellipse through a true gaussian blur — the direct
            // equivalent of the design's `filter: blur(62px)`. RepaintBoundary
            // caches the blurred layer so drag repaints don't re-run the filter.
            Positioned(
              left: 0,
              right: 0,
              bottom: -130,
              child: Center(
                child: RepaintBoundary(
                  child: Opacity(
                    opacity: 0.12 + u * 0.5,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                          sigmaX: haloSigma, sigmaY: haloSigma, tileMode: TileMode.decal),
                      child: Container(
                        width: sz,
                        height: sz * 0.86,
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, color: haloColor(u)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // The card content.
            GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onLongPress: widget.onRemove,
              child: Transform.translate(
                offset: Offset(_dx, 0),
                child: Transform.rotate(
                  angle: _dx / 2400, // slight tilt with the drag
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.task.title,
                            style: const TextStyle(
                              fontFamily: 'Newsreader',
                              fontWeight: FontWeight.w500,
                              fontSize: 40.4,
                              height: 1.16,
                              letterSpacing: -0.6,
                              color: Palette.ink,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 30,
                        child: _Hint(label: '✓ DONE', color: Palette.accent, opacity: _doneOpacity),
                      ),
                      Positioned(
                        top: 0,
                        right: 30,
                        child: _Hint(label: 'SKIP ✕', color: const Color(0xFF6F8099), opacity: _skipOpacity),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.label, required this.color, required this.opacity});

  final String label;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(
          label,
          style: const TextStyle(
              fontFamily: 'Nunito Sans', fontWeight: FontWeight.w800, fontSize: 11.1, letterSpacing: 1.3, color: Colors.white),
        ),
      ),
    );
  }
}
