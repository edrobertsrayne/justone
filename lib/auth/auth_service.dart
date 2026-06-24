import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The auth boundary: Google Sign-In + Firebase credential exchange (D8).
abstract class AuthService {
  Future<void> signInWithGoogle();
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;
  bool _initialized = false;

  @override
  Future<void> signInWithGoogle() async {
    if (!_initialized) {
      await GoogleSignIn.instance.initialize();
      _initialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate(); // throws GoogleSignInException on cancel/error
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await _auth.signInWithCredential(credential);
  }

  @override
  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}
