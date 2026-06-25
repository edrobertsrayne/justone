import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/pool_controller.dart';
import '../app/providers.dart';
import '../domain/task.dart';
import '../domain/urgency.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';
import 'add_sheet.dart';
import 'settings_screen.dart';

class ManageScreen extends ConsumerWidget {
  const ManageScreen({super.key});

  Color _dot(double u) => u > 0.7 ? Palette.terracotta : (u > 0.4 ? const Color(0xFFCDB16A) : const Color(0xFFA9BF9C));

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Task task) async {
    final user = ref.read(userProvider).value;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete this chore?', style: TypeScale.serif(19.9, weight: FontWeight.w500, color: Palette.ink)),
        content: Text('“${task.title}” will be gone for good. This can’t be undone.',
            style: TypeScale.sans(14, height: 1.5, color: Palette.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TypeScale.sans(14, weight: FontWeight.w700, color: Palette.terracotta)),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(poolControllerProvider).remove(user, task);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(userProvider); // keep the stream alive so _confirmDelete's read is populated
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final now = ref.watch(nowProvider)();
    final pool = tasks.where((t) => t.status == TaskStatus.active || t.status == TaskStatus.benched).toList()
      ..sort((a, b) => urgencyOf(b, now).compareTo(urgencyOf(a, now)));

    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ChromeButton(child: const Icon(Icons.chevron_left, color: Color(0xFF6F6A60)), onTap: () => Navigator.of(context).pop()),
                  Text('Your pool', style: TypeScale.serif(15.8, weight: FontWeight.w600, color: Palette.ink)),
                  _ChromeButton(
                    child: const Icon(Icons.settings_outlined, size: 19, color: Color(0xFF8A847A)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                itemCount: pool.length,
                itemBuilder: (context, i) {
                  final t = pool[i];
                  return GestureDetector(
                    onTap: () => showEditSheet(context, ref, t),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: _dot(urgencyOf(t, now)))),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.title, style: TypeScale.serif(15.8, weight: FontWeight.w500, color: Palette.ink)),
                            const SizedBox(height: 5),
                            Text(manageMeta(t, now), style: TypeScale.sans(11.1, weight: FontWeight.w600, color: const Color(0xFFA8A193))),
                          ]),
                        ),
                        GestureDetector(
                          key: ValueKey('delete-${t.id}'),
                          onTap: () => _confirmDelete(context, ref, t),
                          child: const Icon(Icons.delete_outline, size: 18, color: Palette.terracotta),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: GestureDetector(
        onTap: () => showAddSheet(context, ref),
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(19)),
          child: const Icon(Icons.add, color: Palette.paper),
        ),
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)), child: child),
      );
}
