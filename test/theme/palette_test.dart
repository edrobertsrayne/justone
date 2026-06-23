import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/theme/palette.dart';

void main() {
  test('tokens use the exact spec hex values', () {
    expect(Palette.paper, const Color(0xFFF3F1EC));
    expect(Palette.ink, const Color(0xFF2B2824));
    expect(Palette.accent, const Color(0xFF5F8C63));
    expect(Palette.terracotta, const Color(0xFFC2683F));
  });

  test('haloColor interpolates calm -> urgent', () {
    expect(haloColor(0), const Color.fromARGB(255, 95, 140, 99));
    expect(haloColor(1), const Color.fromARGB(255, 196, 104, 63));
    final mid = haloColor(0.5);
    expect(mid.red, closeTo(145, 1));
    expect(mid.green, closeTo(122, 1));
    expect(mid.blue, closeTo(81, 1));
  });

  test('haloColor clamps out-of-range input', () {
    expect(haloColor(-1), haloColor(0));
    expect(haloColor(2), haloColor(1));
  });
}
