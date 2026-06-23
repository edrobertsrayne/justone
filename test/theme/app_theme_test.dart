import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/theme/app_theme.dart';
import 'package:justone/theme/palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme uses paper scaffold and accent seed, light brightness', () {
    final theme = buildAppTheme();
    expect(theme.scaffoldBackgroundColor, Palette.paper);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.brightness, Brightness.light);
  });
}
