import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Stand-in for screens that arrive in Phase 4/5 (manage / stats / add). The
/// route is real; only the body is swapped later.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      appBar: AppBar(title: Text(title), backgroundColor: Palette.paper),
      body: Center(
        child: Text('$title — coming soon',
            style: const TextStyle(color: Palette.muted)),
      ),
    );
  }
}
