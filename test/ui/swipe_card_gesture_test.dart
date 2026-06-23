import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/ui/swipe_card.dart';

Task _t() => Task(id: 'x', title: 'Water the plants', kind: TaskKind.oneOff, createdAt: DateTime(2026, 6, 1));

Widget _host({required bool canSkip, required Map<String, bool> hits}) => MaterialApp(
      home: Scaffold(
        body: SwipeCard(
          task: _t(),
          urgency: 0.5,
          canSkip: canSkip,
          onComplete: () => hits['complete'] = true,
          onSkip: () => hits['skip'] = true,
          onSkipDenied: () => hits['denied'] = true,
          onRemove: () => hits['remove'] = true,
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drag right past threshold completes', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: true, hits: hits));
    await tester.drag(find.byType(SwipeCard), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(hits['complete'], isTrue);
  });

  testWidgets('drag left past threshold skips when allowed', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: true, hits: hits));
    await tester.drag(find.byType(SwipeCard), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(hits['skip'], isTrue);
    expect(hits['denied'], isNull);
  });

  testWidgets('drag left past threshold is denied when out of skips', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: false, hits: hits));
    await tester.drag(find.byType(SwipeCard), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(hits['denied'], isTrue);
    expect(hits['skip'], isNull);
  });

  testWidgets('small drag springs back without firing', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: true, hits: hits));
    await tester.drag(find.byType(SwipeCard), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(hits['complete'], isNull);
    expect(hits['skip'], isNull);
  });

  testWidgets('long-press removes', (tester) async {
    final hits = <String, bool>{};
    await tester.pumpWidget(_host(canSkip: true, hits: hits));
    await tester.longPress(find.byType(SwipeCard));
    await tester.pumpAndSettle();
    expect(hits['remove'], isTrue);
  });
}
