import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/ui/widgets/target_stepper.dart';

void main() {
  testWidgets('+ increments, − decrements, clamped 1..6', (tester) async {
    int value = 3;
    Widget build(int v) => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) => TargetStepper(
                value: v,
                onChanged: (n) => setState(() => value = n),
              ),
            ),
          ),
        );
    await tester.pumpWidget(build(value));
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('target-inc')));
    await tester.pump();
    expect(value, 4);

    value = 6;
    await tester.pumpWidget(build(value));
    await tester.tap(find.byKey(const ValueKey('target-inc')));
    await tester.pump();
    expect(value, 6); // clamped at max

    value = 1;
    await tester.pumpWidget(build(value));
    await tester.tap(find.byKey(const ValueKey('target-dec')));
    await tester.pump();
    expect(value, 1); // clamped at min
  });
}
