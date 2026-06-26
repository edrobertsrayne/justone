import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/settings_controller.dart';
import '../auth/auth_providers.dart';
import '../domain/user_state.dart';
import '../notifications/messaging_service.dart';
import '../notifications/registration_controller.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';
import 'widgets/target_stepper.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _weekend = false;

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  List<String> _activeList(UserState u) => _weekend ? u.remindersWeekend : u.remindersWeekday;

  Future<void> _writeReminders(UserState u, List<String> next) {
    final ctrl = ref.read(settingsControllerProvider);
    return _weekend
        ? ctrl.setReminders(u, weekday: u.remindersWeekday, weekend: next)
        : ctrl.setReminders(u, weekday: next, weekend: u.remindersWeekend);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider).value;
    if (user == null) return const Scaffold(backgroundColor: Palette.paper, body: SizedBox.expand());
    final list = _activeList(user);
    final perm = ref.watch(notifPermissionProvider).value;

    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                GestureDetector(onTap: () => Navigator.of(context).pop(), child: const SizedBox(width: 40, child: Icon(Icons.chevron_left, color: Color(0xFF6F6A60)))),
                Text('Reminders', style: TypeScale.serif(15.8, weight: FontWeight.w600, color: Palette.ink)),
                const SizedBox(width: 40),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                children: [
                  if (perm != null && perm != NotifPermission.granted) ...[
                    _reEnableCard(),
                    const SizedBox(height: 12),
                  ],
                  _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Daily target', style: TypeScale.serif(15.8, weight: FontWeight.w500, color: Palette.ink)),
                      const SizedBox(height: 5),
                      Text('Tasks before today counts as a win', style: TypeScale.sans(11.1, color: const Color(0xFFA8A193))),
                    ]),
                    TargetStepper(value: user.target, numeralSize: 28.4, onChanged: (n) => ref.read(settingsControllerProvider).setTarget(user, n)),
                  ])),
                  const SizedBox(height: 18),
                  _tabs(),
                  const SizedBox(height: 12),
                  for (var i = 0; i < list.length; i++)
                    _reminderRow(user, list, i),
                  if (list.length < 3) _addRow(user, list),
                  const SizedBox(height: 22),
                  _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Signed in · sync on', style: TypeScale.sans(14, weight: FontWeight.w600, color: const Color(0xFF6F6A60))),
                    GestureDetector(
                      onTap: () => ref.read(authServiceProvider).signOut(),
                      child: Text('Sign out', style: TypeScale.sans(12.4, weight: FontWeight.w700, color: Palette.terracotta)),
                    ),
                  ])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text(label, style: TypeScale.sans(12.4, weight: FontWeight.w700, color: active ? Palette.ink : const Color(0xFFA8A193))),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE9E5DC), borderRadius: BorderRadius.circular(13)),
      child: Row(children: [
        tab('Weekdays', !_weekend, () => setState(() => _weekend = false)),
        tab('Weekends', _weekend, () => setState(() => _weekend = true)),
      ]),
    );
  }

  Widget _reminderRow(UserState user, List<String> list, int i) {
    return _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      GestureDetector(
        onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: _parse(list[i]));
          if (picked != null) {
            final next = [...list]..[i] = _fmt(picked);
            await _writeReminders(user, next);
          }
        },
        child: Text(list[i], style: TypeScale.serif(15.8, weight: FontWeight.w500, color: Palette.ink)),
      ),
      GestureDetector(
        key: ValueKey('remove-reminder-$i'),
        onTap: () => _writeReminders(user, [...list]..removeAt(i)),
        child: const Icon(Icons.close, size: 18, color: Palette.terracotta),
      ),
    ]));
  }

  Widget _addRow(UserState user, List<String> list) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
        if (picked != null) await _writeReminders(user, [...list, _fmt(picked)]);
      },
      child: _card(Row(children: [
        const Icon(Icons.add, size: 18, color: Color(0xFF8A847A)),
        const SizedBox(width: 8),
        Text('Add a reminder', style: TypeScale.sans(14, weight: FontWeight.w600, color: const Color(0xFF6F6A60))),
      ])),
    );
  }

  Widget _reEnableCard() => GestureDetector(
        key: const ValueKey('reenable-reminders'),
        onTap: () async {
          await ref.read(registrationControllerProvider).requestAndRegister();
          ref.invalidate(notifPermissionProvider);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            color: Palette.accent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_off_outlined, size: 20, color: Color(0xFFFBF9F4)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reminders are off',
                    style: TypeScale.sans(14, weight: FontWeight.w700, color: const Color(0xFFFBF9F4))),
                const SizedBox(height: 3),
                Text('Tap to turn them on. If nothing happens, enable notifications for Just One in system settings.',
                    style: TypeScale.sans(11.1, height: 1.4, color: const Color(0xFFEDEFE8))),
              ]),
            ),
          ]),
        ),
      );

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}
