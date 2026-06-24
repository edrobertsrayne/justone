// test/domain/routing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/domain/routing.dart';

void main() {
  final now = DateTime(2026, 6, 23, 12);
  final user = UserState(timezone: 'UTC', lastActiveDate: now, onboardingComplete: true);

  Task due(String id) => Task(
        id: id, title: id, kind: TaskKind.recurring, intervalDays: 7,
        dueAt: now, createdAt: DateTime(2026, 1, 1),
      );
  Task notDue(String id) => Task(
        id: id, title: id, kind: TaskKind.recurring, intervalDays: 7,
        dueAt: now.add(const Duration(days: 21)), createdAt: DateTime(2026, 1, 1),
      );

  test('no tasks -> emptyPool', () {
    expect(routeHome(user, const [], now), AppScreen.emptyPool);
  });

  test('archived-only pool still counts as empty', () {
    final archived = due('a').copyWith(status: TaskStatus.archived);
    expect(routeHome(user, [archived], now), AppScreen.emptyPool);
  });

  test('target met and not dismissed -> targetHit', () {
    final hit = user.copyWith(target: 1, doneToday: 1);
    expect(routeHome(hit, [due('a')], now), AppScreen.targetHit);
  });

  test('target met but dismissed falls through to daily', () {
    final hit = user.copyWith(target: 1, doneToday: 1, targetDismissed: true);
    expect(routeHome(hit, [due('a')], now), AppScreen.daily);
  });

  test('tasks present but none due -> cleared', () {
    expect(routeHome(user, [notDue('a')], now), AppScreen.cleared);
  });

  test('a due task -> daily', () {
    expect(routeHome(user, [due('a')], now), AppScreen.daily);
  });

  test('not onboarded -> onboardTarget regardless of pool', () {
    final fresh = UserState(timezone: 'UTC', lastActiveDate: now); // onboardingComplete defaults false
    expect(routeHome(fresh, const [], now), AppScreen.onboardTarget);
    expect(routeHome(fresh, [due('a')], now), AppScreen.onboardTarget);
  });
}
