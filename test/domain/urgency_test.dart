import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/urgency.dart';

Task recurring({required int interval, required DateTime dueAt}) => Task(
      id: 'r', title: 'r', kind: TaskKind.recurring,
      intervalDays: interval, dueAt: dueAt, createdAt: DateTime(2026, 1, 1),
    );

void main() {
  final now = DateTime(2026, 6, 23, 12);

  test('daysBetweenLocalDates counts calendar days, DST-safe', () {
    expect(daysBetweenLocalDates(DateTime(2026, 6, 23), DateTime(2026, 6, 24)), 1);
    expect(daysBetweenLocalDates(DateTime(2026, 6, 24), DateTime(2026, 6, 23)), -1);
    // across a UK spring-forward boundary (29 Mar 2026) still exactly 1 day
    expect(daysBetweenLocalDates(DateTime(2026, 3, 28), DateTime(2026, 3, 29)), 1);
  });

  test('due today is ~0.51', () {
    final u = urgencyOf(recurring(interval: 7, dueAt: now), now);
    expect(u, closeTo(0.51, 0.02));
  });

  test('one full cycle overdue is ~0.87', () {
    final due = now.subtract(const Duration(days: 7));
    final u = urgencyOf(recurring(interval: 7, dueAt: due), now);
    expect(u, closeTo(0.87, 0.02));
  });

  test('far from due falls to the 0.04 floor (not due)', () {
    final due = now.add(const Duration(days: 21)); // r = -3 for interval 7
    final u = urgencyOf(recurring(interval: 7, dueAt: due), now);
    expect(u, closeTo(0.04, 0.01));
    expect(u, lessThanOrEqualTo(0.04 + 0.005));
  });

  test('undated one-off returns the constant low-band baseline', () {
    final t = Task(
      id: 'o', title: 'fix shelf', kind: TaskKind.oneOff,
      createdAt: DateTime(2026, 1, 1),
    );
    expect(urgencyOf(t, now), 0.35);
  });

  test('one-off with a deadline uses the 7-day horizon', () {
    final t = Task(
      id: 'o2', title: 'cancel sub', kind: TaskKind.oneOff,
      dueAt: now, createdAt: DateTime(2026, 1, 1),
    );
    expect(urgencyOf(t, now), closeTo(0.51, 0.02)); // due today, r=0
  });
}
