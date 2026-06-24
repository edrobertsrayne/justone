import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../auth/auth_providers.dart';
import '../theme/palette.dart';

/// Minimal functional auth gate (D8). Phase 4 replaces this with the designed
/// welcome screen. On success, authStateChanges drives AuthGate forward; this
/// screen does not navigate.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _error = 'Sign-in failed. Please try again.';
      }
    } catch (_) {
      _error = 'Sign-in failed. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Just One', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 48),
            if (_loading)
              const CircularProgressIndicator()
            else
              FilledButton(onPressed: _signIn, child: const Text('Continue with Google')),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Palette.terracotta)),
            ],
          ],
        ),
      ),
    );
  }
}
