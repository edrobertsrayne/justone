import 'package:flutter/material.dart';

import 'palette.dart';
import 'type_scale.dart';

/// The single light theme for Just One (paper/ink aesthetic, HANDOFF §6).
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.light,
  ).copyWith(surface: Palette.paper);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Palette.paper,
    textTheme: TextTheme(
      bodyMedium: TypeScale.sans(TypeScale.body, color: Palette.ink),
      titleMedium: TypeScale.serif(TypeScale.title, color: Palette.ink),
      headlineMedium: TypeScale.serif(TypeScale.headline, color: Palette.ink),
      displaySmall: TypeScale.serif(TypeScale.display, color: Palette.ink),
    ),
  );
}
