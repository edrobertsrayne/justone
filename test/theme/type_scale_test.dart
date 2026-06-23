import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/theme/type_scale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('body anchors the scale at 14', () {
    expect(TypeScale.body, 14.0);
  });

  test('ladder steps follow the 1.125 major-second ratio', () {
    expect(TypeScale.title / TypeScale.body, closeTo(1.125, 0.01));
  });

  test('serif/sans builders apply size and weight', () {
    final s = TypeScale.serif(TypeScale.headline, weight: FontWeight.w500);
    expect(s.fontSize, closeTo(TypeScale.headline, 0.01));
    expect(s.fontWeight, FontWeight.w500);
  });
}
