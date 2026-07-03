import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth/auth_gate.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'ui/toast.dart';

/// Emulator on by default in debug; override for a real-device push test with
/// `--dart-define=USE_EMULATOR=false`.
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: kDebugMode);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship as bundled assets (see pubspec.yaml). Never fetch from
  // fonts.gstatic.com at runtime: it fails offline and crashed the app on a
  // host-lookup error. A missing weight now throws in dev instead of at users.
  GoogleFonts.config.allowRuntimeFetching = false;
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
