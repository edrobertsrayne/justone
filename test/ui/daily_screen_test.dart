import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/daily_screen.dart';
import 'package:justone/ui/placeholder_screen.dart';
import 'package:justone/ui/swipe_card.dart';

UserState _user() => UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 23), rerolls: 3);
Task _t() => Task(id: 'x', title: 'Water the plants', kind: TaskKind.recurring, intervalDays: 3, dueAt: DateTime(2026, 6, 23), createdAt: DateTime(2026, 6, 1));

Widget _app() => ProviderScope(
      overrides: [nowProvider.overrideWithValue(() => DateTime(2026, 6, 23, 9))],
      child: MaterialApp(home: DailyScreen(user: _user(), task: _t())),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders chrome + the served card', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byType(SwipeCard), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);
  });

  testWidgets('the FAB opens the add placeholder', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byKey(const ValueKey('daily-fab')));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceholderScreen), findsOneWidget);
    expect(find.textContaining('Add'), findsWidgets);
  });
}
