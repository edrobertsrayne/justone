import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The daily-flow screens (daily_screen, swipe_card, stats_screen, …) style text
/// with bare `TextStyle(fontFamily: 'Newsreader' / 'Nunito Sans')`. Those names
/// only resolve if the families are declared in pubspec's `fonts:` section —
/// google_fonts registers under different, mangled names, so it doesn't cover
/// these. Without the declaration the engine falls back to a platform serif and
/// the whole app looks wrong. Guard the declaration so it can't silently regress.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Newsreader and Nunito Sans are declared as bundled font families', () async {
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    final families = {for (final e in manifest) (e as Map)['family'] as String};
    expect(families, containsAll(<String>['Newsreader', 'Nunito Sans']));
  });
}
