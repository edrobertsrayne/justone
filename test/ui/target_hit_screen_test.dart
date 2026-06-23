import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/target_hit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows both stats and fires onKeepGoing', (tester) async {
    var kept = false;
    final user = UserState(
        timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23), target: 3, streak: 5, targetMetDays: 12);
    await tester.pumpWidget(
        MaterialApp(home: TargetHitScreen(user: user, onKeepGoing: () => kept = true)));
    expect(find.textContaining('Daily target met'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // streak
    expect(find.text('12'), findsOneWidget); // targetMetDays
    expect(find.textContaining('DAY STREAK'), findsOneWidget);
    expect(find.textContaining('ON TARGET'), findsOneWidget);
    await tester.tap(find.text('Keep going!'));
    expect(kept, isTrue);
  });
}
