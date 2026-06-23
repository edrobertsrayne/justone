import 'dart:ui';

/// Static colour tokens for the paper/ink aesthetic (HANDOFF §6).
abstract final class Palette {
  static const Color paper = Color(0xFFF3F1EC);
  static const Color ink = Color(0xFF2B2824);
  static const Color mutedStrong = Color(0xFF5C574E);
  static const Color muted = Color(0xFF8F8A80);
  static const Color accent = Color(0xFF5F8C63);
  static const Color terracotta = Color(0xFFC2683F);
  static const Color iconCream = Color(0xFFEFEAE0);
}

const Color _haloCalm = Color.fromARGB(255, 95, 140, 99);
const Color _haloUrgent = Color.fromARGB(255, 196, 104, 63);

/// Urgency -> halo colour (the prototype's `mix(u)`); [u] clamped to [0,1].
Color haloColor(double u) {
  return Color.lerp(_haloCalm, _haloUrgent, u.clamp(0.0, 1.0))!;
}
