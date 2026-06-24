import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/auth/bootstrap.dart';

void main() {
  test('creates a default user doc when missing', () async {
    final db = FakeFirebaseFirestore();
    await ensureUserDoc(db, 'u1', now: DateTime(2026, 6, 24, 9), timezone: 'Europe/London');
    final data = (await db.doc('users/u1').get()).data()!;
    expect(data['onboardingComplete'], false);
    expect(data['timezone'], 'Europe/London');
    expect(data['target'], 3);
    expect(data['rerolls'], 3);
    expect(data['lifetimeDone'], 0);
    expect(data['lastActiveDate'], '2026-06-24');
    expect(data['reminders'], {'weekday': ['08:00', '18:30', '21:00'], 'weekend': ['10:00', '20:00']});
  });

  test('only refreshes timezone when the doc already exists', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u1').set({
      'timezone': 'UTC', 'target': 5, 'streak': 7, 'lifetimeDone': 99,
      'reminders': {'weekday': <String>[], 'weekend': <String>[]},
      'onboardingComplete': true, 'lastActiveDate': '2026-06-20',
    });
    await ensureUserDoc(db, 'u1', now: DateTime(2026, 6, 24), timezone: 'Asia/Tokyo');
    final data = (await db.doc('users/u1').get()).data()!;
    expect(data['timezone'], 'Asia/Tokyo'); // refreshed
    expect(data['streak'], 7); // untouched
    expect(data['lifetimeDone'], 99); // untouched
    expect(data['target'], 5); // untouched
  });
}
