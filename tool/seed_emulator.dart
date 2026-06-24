// Dev-only: seed the Firebase emulator with an onboarded user + sample tasks so
// the daily loop is hand-testable before Phase-4 onboarding exists.
//
// Run with the emulator up:
//   firebase emulators:start
//   flutter run -t tool/seed_emulator.dart -d <device>
//
// It signs in anonymously against the Auth emulator, writes users/{uid} with
// onboardingComplete:true and the InMemoryRepository.seeded() pool, then prints
// the uid. NOT shipped; not referenced from lib/.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'package:justone/data/firestore_mappers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);

  final cred = await FirebaseAuth.instance.signInAnonymously();
  final uid = cred.user!.uid;
  final seed = InMemoryRepository.seeded();
  final user = await seed.watchUser().first;
  final tasks = await seed.watchTasks().first;

  final db = FirebaseFirestore.instance;
  await db.doc('users/$uid').set(userToFirestore(user));
  for (final t in tasks) {
    await db.doc('users/$uid/tasks/${t.id}').set(taskToFirestore(t));
  }
  // ignore: avoid_print
  print('Seeded emulator user: $uid (${tasks.length} tasks)');
}
