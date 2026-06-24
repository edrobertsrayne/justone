import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../app/providers.dart';
import '../data/firestore_mappers.dart';
import '../domain/user_state.dart';
import 'auth_providers.dart';

/// First-run bootstrap (D13): create `users/{uid}` with defaults if missing,
/// otherwise just refresh the timezone (D2). Idempotent.
Future<void> ensureUserDoc(
  FirebaseFirestore db,
  String uid, {
  required DateTime now,
  required String timezone,
}) async {
  final ref = db.doc('users/$uid');
  final snap = await ref.get();
  if (!snap.exists) {
    final defaults = UserState(
      timezone: timezone,
      target: 3,
      remindersWeekday: const ['08:00', '18:30', '21:00'],
      remindersWeekend: const ['10:00', '20:00'],
      onboardingComplete: false,
      lastActiveDate: DateTime(now.year, now.month, now.day),
    );
    await ref.set(userToFirestore(defaults));
  } else {
    await ref.set({'timezone': timezone}, SetOptions(merge: true));
  }
}

/// Runs [ensureUserDoc] for the signed-in user; the AuthGate awaits this before
/// rendering the app, so the UI never renders against a missing doc.
final bootstrapProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(authProvider).value?.uid;
  if (uid == null) return;
  final db = ref.watch(firestoreProvider);
  final now = ref.watch(nowProvider)();
  final tz = (await FlutterTimezone.getLocalTimezone()).identifier;
  await ensureUserDoc(db, uid, now: now, timezone: tz);
});
