import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/pool_controller.dart';
import '../app/providers.dart';
import '../domain/edits.dart';
import '../domain/task.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';

/// Deadline + repeat enrichment. [existing] => edit; otherwise add [title].
Future<void> showEnrichSheet(BuildContext context, WidgetRef ref,
    {String? title, Task? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EnrichSheet(title: title, existing: existing),
  );
}

class _EnrichSheet extends ConsumerStatefulWidget {
  const _EnrichSheet({this.title, this.existing});
  final String? title;
  final Task? existing;
  @override
  ConsumerState<_EnrichSheet> createState() => _EnrichSheetState();
}

class _EnrichSheetState extends ConsumerState<_EnrichSheet> {
  late DeadlineChoice _deadline;
  late RepeatChoice _repeat;
  late int _customN;
  late CustomUnit _customUnit;
  DateTime? _pickedDate;

  @override
  void initState() {
    super.initState();
    final now = ref.read(nowProvider)();
    final t = widget.existing;
    _deadline = t == null ? DeadlineChoice.none : deadlineChoiceFor(t.dueAt, now);
    _pickedDate = (_deadline == DeadlineChoice.pickDate) ? t!.dueAt : null;
    final r = t == null
        ? (choice: RepeatChoice.oneOff, customN: 2, customUnit: CustomUnit.weeks)
        : repeatChoiceFor(t.kind, t.intervalDays);
    _repeat = r.choice;
    _customN = r.customN;
    _customUnit = r.customUnit;
  }

  String get _title => widget.existing?.title ?? widget.title ?? '';

  Future<void> _pickDate() async {
    final now = ref.read(nowProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() { _deadline = DeadlineChoice.pickDate; _pickedDate = picked; });
  }

  Future<void> _save() async {
    final user = ref.read(userProvider).value;
    if (user == null) { Navigator.of(context).pop(); return; }
    final pool = ref.read(poolControllerProvider);
    final existing = widget.existing;
    if (existing == null) {
      await pool.add(user,
          title: _title, deadline: _deadline, pickedDate: _pickedDate,
          repeat: _repeat, customN: _customN, customUnit: _customUnit);
    } else {
      await pool.edit(user, existing,
          title: _title, deadline: _deadline, pickedDate: _pickedDate,
          repeat: _repeat, customN: _customN, customUnit: _customUnit);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Watching (not just reading) keeps userProvider alive and resolved for
    // the sheet's lifetime, scoped to this ConsumerState's own ref so it's
    // auto-cancelled on dispose; _save reads the resolved value via ref.read.
    ref.watch(userProvider);
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2DCCF), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(_title, style: TypeScale.serif(22.4, weight: FontWeight.w500, color: Palette.ink)),
          const SizedBox(height: 20),
          _sectionLabel('Deadline'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final entry in const [
              (DeadlineChoice.none, 'No deadline'), (DeadlineChoice.today, 'Today'),
              (DeadlineChoice.tomorrow, 'Tomorrow'), (DeadlineChoice.thisWeek, 'This week'),
              (DeadlineChoice.nextWeek, 'Next week'),
            ])
              _chip(entry.$2, _deadline == entry.$1, () => setState(() { _deadline = entry.$1; _pickedDate = null; })),
            _chip(_pickedDate == null ? '◷ Pick a date' : '◷ ${_pickedDate!.year}-${_pickedDate!.month.toString().padLeft(2, '0')}-${_pickedDate!.day.toString().padLeft(2, '0')}',
                _deadline == DeadlineChoice.pickDate, _pickDate, special: true),
          ]),
          const SizedBox(height: 18),
          _sectionLabel('Repeat'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final entry in const [
              (RepeatChoice.oneOff, 'One-off'), (RepeatChoice.every3, 'Every 3 days'),
              (RepeatChoice.weekly, 'Weekly'), (RepeatChoice.fortnightly, 'Fortnightly'),
              (RepeatChoice.monthly, 'Monthly'),
            ])
              _chip(entry.$2, _repeat == entry.$1, () => setState(() => _repeat = entry.$1)),
            _chip('⊕ Custom', _repeat == RepeatChoice.custom, () => setState(() => _repeat = RepeatChoice.custom), special: true),
          ]),
          if (_repeat == RepeatChoice.custom) _customPanel(),
          const SizedBox(height: 22),
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFF1EDE4), borderRadius: BorderRadius.circular(14)),
                child: Text('Back', style: TypeScale.sans(14, weight: FontWeight.w700, color: const Color(0xFF8A847A))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: Text('Save', style: TypeScale.sans(14, weight: FontWeight.w700, color: Palette.paper)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _customPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F1),
        border: Border.all(color: const Color(0xFFB7CDB4), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CUSTOM REPEAT', style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 0.6, color: Palette.accent)),
        const SizedBox(height: 12),
        Row(children: [
          Text('Every', style: TypeScale.sans(11.1, weight: FontWeight.w700, color: const Color(0xFFA8A193))),
          const SizedBox(width: 12),
          GestureDetector(
            key: const ValueKey('custom-dec'),
            onTap: () => setState(() => _customN = (_customN - 1).clamp(1, 99)),
            child: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(width: 46, child: Text('$_customN', textAlign: TextAlign.center, style: TypeScale.serif(25.2, weight: FontWeight.w600, color: Palette.ink))),
          GestureDetector(
            key: const ValueKey('custom-inc'),
            onTap: () => setState(() => _customN = (_customN + 1).clamp(1, 99)),
            child: const Icon(Icons.add_circle_outline),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final u in CustomUnit.values)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _customUnit = u),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _customUnit == u ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(_unitLabel(u), style: TypeScale.sans(12.5, weight: FontWeight.w700, color: _customUnit == u ? Palette.ink : const Color(0xFF8A847A))),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  String _unitLabel(CustomUnit u) => switch (u) {
        CustomUnit.days => 'Days',
        CustomUnit.weeks => 'Weeks',
        CustomUnit.months => 'Months',
      };

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(s, style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 0.4, color: const Color(0xFFA8A193))),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap, {bool special = false}) {
    final bg = selected ? (special ? Palette.accent : Palette.ink) : (special ? const Color(0xFFF3F6F1) : Colors.white);
    final fg = selected ? (special ? const Color(0xFFFBF9F4) : Palette.paper) : (special ? Palette.accent : const Color(0xFF6F6A60));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: selected ? bg : const Color(0xFFE7E2D8), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: TypeScale.sans(12.5, weight: FontWeight.w700, color: fg)),
      ),
    );
  }
}
