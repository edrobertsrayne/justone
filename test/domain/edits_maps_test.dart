// test/domain/edits_maps_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/edits.dart';

void main() {
  final now = DateTime(2026, 6, 24, 9); // a Wednesday, 09:00

  group('dueAtFor', () {
    test('none -> null', () => expect(dueAtFor(DeadlineChoice.none, now), isNull));
    test('today -> midnight today', () =>
        expect(dueAtFor(DeadlineChoice.today, now), DateTime(2026, 6, 24)));
    test('tomorrow -> +1 day', () =>
        expect(dueAtFor(DeadlineChoice.tomorrow, now), DateTime(2026, 6, 25)));
    test('this week -> +7 days', () =>
        expect(dueAtFor(DeadlineChoice.thisWeek, now), DateTime(2026, 7, 1)));
    test('next week -> +14 days', () =>
        expect(dueAtFor(DeadlineChoice.nextWeek, now), DateTime(2026, 7, 8)));
    test('pickDate -> date-only of picked', () =>
        expect(dueAtFor(DeadlineChoice.pickDate, now, pickedDate: DateTime(2026, 8, 3, 14)),
            DateTime(2026, 8, 3)));
  });

  group('deadlineChoiceFor (reverse)', () {
    test('null -> none', () => expect(deadlineChoiceFor(null, now), DeadlineChoice.none));
    test('today', () => expect(deadlineChoiceFor(DateTime(2026, 6, 24), now), DeadlineChoice.today));
    test('tomorrow', () => expect(deadlineChoiceFor(DateTime(2026, 6, 25), now), DeadlineChoice.tomorrow));
    test('+7 -> thisWeek', () => expect(deadlineChoiceFor(DateTime(2026, 7, 1), now), DeadlineChoice.thisWeek));
    test('+14 -> nextWeek', () => expect(deadlineChoiceFor(DateTime(2026, 7, 8), now), DeadlineChoice.nextWeek));
    test('non-preset -> pickDate', () => expect(deadlineChoiceFor(DateTime(2026, 6, 30), now), DeadlineChoice.pickDate));
  });

  group('repeatToFields', () {
    test('oneOff', () => expect(repeatToFields(RepeatChoice.oneOff), (kind: TaskKind.oneOff, intervalDays: null)));
    test('every3', () => expect(repeatToFields(RepeatChoice.every3), (kind: TaskKind.recurring, intervalDays: 3)));
    test('weekly', () => expect(repeatToFields(RepeatChoice.weekly), (kind: TaskKind.recurring, intervalDays: 7)));
    test('fortnightly', () => expect(repeatToFields(RepeatChoice.fortnightly), (kind: TaskKind.recurring, intervalDays: 14)));
    test('monthly', () => expect(repeatToFields(RepeatChoice.monthly), (kind: TaskKind.recurring, intervalDays: 30)));
    test('custom 3 weeks -> 21', () => expect(
        repeatToFields(RepeatChoice.custom, customN: 3, customUnit: CustomUnit.weeks),
        (kind: TaskKind.recurring, intervalDays: 21)));
    test('custom clamps N to 1..99', () => expect(
        repeatToFields(RepeatChoice.custom, customN: 0, customUnit: CustomUnit.days).intervalDays, 1));
  });

  group('repeatChoiceFor (reverse)', () {
    test('oneOff', () => expect(repeatChoiceFor(TaskKind.oneOff, null).choice, RepeatChoice.oneOff));
    test('7 -> weekly', () => expect(repeatChoiceFor(TaskKind.recurring, 7).choice, RepeatChoice.weekly));
    test('30 -> monthly', () => expect(repeatChoiceFor(TaskKind.recurring, 30).choice, RepeatChoice.monthly));
    test('21 -> custom 3 weeks', () {
      final r = repeatChoiceFor(TaskKind.recurring, 21);
      expect((r.choice, r.customN, r.customUnit), (RepeatChoice.custom, 3, CustomUnit.weeks));
    });
    test('60 -> custom 2 months', () {
      final r = repeatChoiceFor(TaskKind.recurring, 60);
      expect((r.choice, r.customN, r.customUnit), (RepeatChoice.custom, 2, CustomUnit.months));
    });
    test('5 -> custom 5 days', () {
      final r = repeatChoiceFor(TaskKind.recurring, 5);
      expect((r.choice, r.customN, r.customUnit), (RepeatChoice.custom, 5, CustomUnit.days));
    });
  });
}
