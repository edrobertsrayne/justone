import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../theme/palette.dart';
import '../theme/type_scale.dart';

/// First-run entry (D8): Google sign-in live; Apple/email shown as future.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TickMark(),
              const SizedBox(height: 24),
              Center(
                  child: Text('Just One',
                      style: TypeScale.serif(45.5, weight: FontWeight.w500, color: Palette.ink))),
              const SizedBox(height: 8),
              Center(
                  child: Text('One task a day. That’s enough.',
                      style: TypeScale.sans(15.8, color: Palette.muted))),
              const SizedBox(height: 48),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                _AuthButton(label: 'Continue with Google', filled: true, onTap: _signIn),
                const SizedBox(height: 10),
                const _AuthButton(label: 'Continue with Apple', filled: false, onTap: null),
                const SizedBox(height: 6),
                const Center(child: _DisabledText('Continue with email')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Center(child: Text(_error!, style: TypeScale.sans(12.4, color: Palette.terracotta))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TickMark extends StatelessWidget {
  const _TickMark();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
          alignment: Alignment.center,
          child: const Icon(Icons.check_rounded, color: Palette.iconCream, size: 40),
        ),
      );
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.label, required this.filled, required this.onTap});
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: filled ? Palette.ink : Colors.white,
          border: filled ? null : Border.all(color: const Color(0xFFE2DCCF), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TypeScale.sans(14,
                weight: FontWeight.w700,
                color: disabled
                    ? const Color(0xFFC2BCAE)
                    : (filled ? Palette.paper : Palette.ink))),
      ),
    );
  }
}

class _DisabledText extends StatelessWidget {
  const _DisabledText(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(label,
            style: TypeScale.sans(12.4, weight: FontWeight.w700, color: const Color(0xFFC2BCAE))),
      );
}
