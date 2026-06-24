import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_gate.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'ui/toast.dart';

/// Emulator on by default in debug; override for a real-device push test with
/// `--dart-define=USE_EMULATOR=false` (D18).
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: kDebugMode);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kUseEmulator) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  }
  runApp(const ProviderScopedApp());
}

/// Whole app incl. the Riverpod scope, so widget tests can pump [JustOneApp] directly.
class ProviderScopedApp extends StatelessWidget {
  const ProviderScopedApp({super.key});

  @override
  Widget build(BuildContext context) => const ProviderScope(child: JustOneApp());
}

class JustOneApp extends StatelessWidget {
  const JustOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Just One',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const Stack(
        children: [
          Positioned.fill(child: AuthGate()),
          ToastOverlay(),
        ],
      ),
    );
  }
}
