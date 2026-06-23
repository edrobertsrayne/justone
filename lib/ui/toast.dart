import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/toast_controller.dart';
import '../theme/palette.dart';

/// Top-anchored, auto-dismissing toast pill. Stack this above screen content.
class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(toastProvider);
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: message == null
              ? const SizedBox.shrink()
              : Center(
                  key: ValueKey(message),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    decoration: BoxDecoration(
                      color: Palette.ink,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Palette.paper,
                        fontFamily: 'Nunito Sans',
                        fontWeight: FontWeight.w600,
                        fontSize: 12.4,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
