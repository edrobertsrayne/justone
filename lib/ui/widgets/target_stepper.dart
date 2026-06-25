import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/type_scale.dart';

/// −  value  +  stepper, clamped to 1..6. Shared by onboarding + settings.
class TargetStepper extends StatelessWidget {
  const TargetStepper({
    required this.value,
    required this.onChanged,
    this.numeralSize = 57.5,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double numeralSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          glyph: '−',
          key: const ValueKey('target-dec'),
          enabled: value > 1,
          onTap: () => onChanged(value - 1),
        ),
        const SizedBox(width: 18),
        Text('$value',
            style: TypeScale.serif(numeralSize, weight: FontWeight.w500, color: Palette.ink)),
        const SizedBox(width: 18),
        _StepButton(
          glyph: '+',
          key: const ValueKey('target-inc'),
          enabled: value < 6,
          onTap: () => onChanged(value + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.glyph, required this.enabled, required this.onTap, super.key});

  final String glyph;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF6F3EC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFE7E2D8), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(glyph,
            style: TypeScale.sans(22,
                weight: FontWeight.w600,
                color: enabled ? Palette.ink : const Color(0xFFCFC9BD))),
      ),
    );
  }
}
