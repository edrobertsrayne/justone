import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/task.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';
import 'enrich_sheet.dart';

/// Quick-add: title only, then hand off to the enrich sheet (prototype flow).
Future<void> showAddSheet(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final title = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2DCCF), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            Text('NEW CHORE', style: TypeScale.sans(9.8, weight: FontWeight.w700, letterSpacing: 1.6, color: const Color(0xFFA8A193))),
            TextField(
              controller: controller,
              autofocus: true,
              style: TypeScale.serif(25.2, weight: FontWeight.w500, color: Palette.ink),
              decoration: const InputDecoration(hintText: 'What needs doing?', border: InputBorder.none),
              onSubmitted: (v) => Navigator.of(sheetContext).pop(v.trim()),
            ),
            const SizedBox(height: 18),
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(sheetContext).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(color: const Color(0xFFF1EDE4), borderRadius: BorderRadius.circular(14)),
                  child: Text('Cancel', style: TypeScale.sans(14, weight: FontWeight.w700, color: const Color(0xFF8A847A))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(sheetContext).pop(controller.text.trim()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: Text('Add to pool', style: TypeScale.sans(14, weight: FontWeight.w700, color: Palette.paper)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
  // Dispose after the sheet's closing animation finishes (post-frame), not
  // immediately: the TextField is still attached mid-dismiss-transition and
  // a disposed controller there throws inside the widgets/rendering layers.
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  if (title == null || title.isEmpty || !context.mounted) return;
  await showEnrichSheet(context, ref, title: title);
}

/// Re-exported for callers that only need a Task edit entry point.
Future<void> showEditSheet(BuildContext context, WidgetRef ref, Task task) =>
    showEnrichSheet(context, ref, existing: task);
