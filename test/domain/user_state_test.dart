// test/domain/user_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/user_state.dart';

void main() {
  final base = UserState(
    timezone: 'Europe/London',
    lastActiveDate: DateTime(2026, 6, 23),
  );

  test('applies documented defaults', () {
    expect(base.target, 3);
    expect(base.rerolls, 3);
    expect(base.streak, 0);
    expect(base.onboardingComplete, isFalse);
    expect(base.remindersWeekday, isEmpty);
  });

  test('copyWith updates only named fields with value equality', () {
    final next = base.copyWith(streak: 2, bankedToday: true);
    expect(next.streak, 2);
    expect(next.bankedToday, isTrue);
    expect(next.timezone, 'Europe/London');
    expect(next, base.copyWith(streak: 2, bankedToday: true));
    expect(next == base, isFalse);
  });
}
