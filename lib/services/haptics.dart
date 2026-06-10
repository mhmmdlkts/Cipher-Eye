import 'package:flutter/services.dart';

/// Thin semantic wrapper around [HapticFeedback] so call sites read by intent
/// (copy, reveal, save, delete …) instead of raw impact levels. Keeps the
/// feel consistent across the app and makes it trivial to retune in one place.
class Haptics {
  Haptics._();

  /// Light tap — frequent, low-stakes actions (copy, list taps).
  static void light() => HapticFeedback.lightImpact();

  /// Toggles, steppers, reveal/hide — the iOS "selection" tick.
  static void selection() => HapticFeedback.selectionClick();

  /// A committed action succeeded (save, unlock).
  static void success() => HapticFeedback.mediumImpact();

  /// Destructive / warning action (delete).
  static void warning() => HapticFeedback.heavyImpact();
}
