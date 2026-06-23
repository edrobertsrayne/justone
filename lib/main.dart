import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';
import 'ui/home_router.dart';
import 'ui/toast.dart';

void main() => runApp(const ProviderScopedApp());

/// Whole app incl. the Riverpod scope, so widget tests can pump it directly.
class ProviderScopedApp extends StatelessWidget {
  const ProviderScopedApp({super.key});

  @override
  Widget build(BuildContext context) => const ProviderScope(child: JustOneApp());
}

class JustOneApp extends StatelessWidget {
  const JustOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Just One',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const Stack(
        children: [
          Positioned.fill(child: HomeRouter()),
          ToastOverlay(),
        ],
      ),
    );
  }
}
