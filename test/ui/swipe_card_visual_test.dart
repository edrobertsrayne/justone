import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/ui/swipe_card.dart';

Task _t() => Task(id: 'x', title: 'Water the plants', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows the task title and no meta/counter text', (tester) async {
    await tester.pumpWidget(_host(SwipeCard(
      task: _t(),
      urgency: 0.6,
      canSkip: true,
      onComplete: () {},
      onSkip: () {},
      onSkipDenied: () {},
      onRemove: () {},
    )));
    expect(find.text('Water the plants'), findsOneWidget);
    // restraint: no due/overdue/streak/counter text on the card
    expect(find.textContaining('overdue'), findsNothing);
    expect(find.textContaining('due'), findsNothing);
  });
}
