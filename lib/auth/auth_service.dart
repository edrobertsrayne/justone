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
    try {
      if (!_initialized) {
        await GoogleSignIn.instance.initialize(
          // Web OAuth client from google-services.json (type 3) — required for
          // GoogleSignIn 7's Credential Manager flow to return a populated idToken.
          serverClientId: '617222535260-3ioaosi1jhbg3ua5nudmrvshjno4cekb.apps.googleusercontent.com',
        );
        _initialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google Sign-In returned no ID token; check the OAuth client configuration.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return; // user backed out — silent
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    if (_initialized) await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}
