import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the current top-toast message (or null). Auto-clears after [show]'s
/// duration; a new [show] replaces the current message and resets the timer.
class ToastController extends Notifier<String?> {
  Timer? _timer;

  @override
  String? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(String message, {Duration duration = const Duration(seconds: 2)}) {
    _timer?.cancel();
    state = message;
    _timer = Timer(duration, () => state = null);
  }
}

final toastProvider = NotifierProvider<ToastController, String?>(ToastController.new);
