import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/onboarding_controller.dart';
import '../app/providers.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';
import 'widgets/target_stepper.dart';

const _suggestions = ['Dishes', 'Laundry', 'Water the plants', 'Reply to emails', 'Take the bins out', 'Make the bed'];

class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});
  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  int _step = 0;
  int _target = 3;
  final _titles = <String>[];
  final _draft = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _addDraft() {
    final t = _draft.text.trim();
    if (t.isEmpty || _titles.contains(t)) {
      _draft.clear();
      return;
    }
    setState(() { _titles.add(t); _draft.clear(); });
  }

  void _toggle(String title) => setState(() {
        _titles.contains(title) ? _titles.remove(title) : _titles.add(title);
      });

  Future<void> _finish() async {
    final user = ref.read(userProvider).value;
    if (user == null || _submitting) return;
    setState(() => _submitting = true);
    await ref.read(onboardingControllerProvider).finish(user, target: _target, titles: _titles);
    // onboardingComplete flips true -> the stream re-emits and HomeRouter re-routes.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: _step == 0 ? _buildTarget() : _buildAdd(),
        ),
      ),
    );
  }

  Widget _buildTarget() {
    return Column(
      children: [
        _eyebrow('Step 1 of 2'),
        const Spacer(),
        Text('DAILY TARGET',
            style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 2.4, color: Palette.accent)),
        const SizedBox(height: 14),
        Text('How much is enough?',
            textAlign: TextAlign.center,
            style: TypeScale.serif(31.9, weight: FontWeight.w500, color: Palette.ink)),
        const SizedBox(height: 12),
        SizedBox(
          width: 220,
          child: Text("Finish this many in a day and you've done enough. Change it whenever.",
              textAlign: TextAlign.center, style: TypeScale.sans(14, height: 1.55, color: Palette.muted)),
        ),
        const SizedBox(height: 28),
        TargetStepper(value: _target, onChanged: (n) => setState(() => _target = n)),
        const Spacer(),
        _primary('Continue', () => setState(() => _step = 1)),
      ],
    );
  }

  Widget _buildAdd() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          GestureDetector(
            onTap: () => setState(() => _step = 0),
            child: const Icon(Icons.chevron_left, color: Color(0xFF6F6A60)),
          ),
          const Spacer(),
          _eyebrow('Step 2 of 2'),
          const Spacer(),
          const SizedBox(width: 24),
        ]),
        const SizedBox(height: 18),
        Text("What's on your plate?",
            style: TypeScale.serif(28.4, weight: FontWeight.w500, color: Palette.ink)),
        const SizedBox(height: 10),
        Text("Add a few. We'll surface one at a time — never the whole list.",
            style: TypeScale.sans(14, height: 1.5, color: Palette.muted)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _draft,
              onSubmitted: (_) => _addDraft(),
              decoration: InputDecoration(
                hintText: 'Add a chore…',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _addDraft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(12)),
              child: Text('Add', style: TypeScale.sans(12.4, weight: FontWeight.w700, color: Palette.paper)),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              _Chip(label: s, selected: _titles.contains(s), onTap: () => _toggle(s)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              for (final t in _titles)
                ListTile(
                  dense: true,
                  title: Text(t, style: TypeScale.serif(15.8, weight: FontWeight.w500, color: Palette.ink)),
                  trailing: GestureDetector(
                    onTap: () => setState(() => _titles.remove(t)),
                    child: const Icon(Icons.close, size: 18, color: Palette.terracotta),
                  ),
                ),
            ],
          ),
        ),
        _primary('Start Just One', _titles.isEmpty || _submitting ? null : _finish),
      ],
    );
  }

  Widget _eyebrow(String s) => Text(s.toUpperCase(),
      style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 1.8, color: const Color(0xFFB3AC9E)));

  Widget _primary(String label, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: onTap == null ? const Color(0xFFB8B2A6) : Palette.ink,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TypeScale.sans(14, weight: FontWeight.w700, color: Palette.paper)),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Palette.accent : Colors.white,
          border: Border.all(color: selected ? Palette.accent : const Color(0xFFE7E2D8), width: 1.5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(selected ? '✓ $label' : label,
            style: TypeScale.sans(12, weight: FontWeight.w700, color: selected ? const Color(0xFFFBF9F4) : const Color(0xFF6F6A60))),
      ),
    );
  }
}
