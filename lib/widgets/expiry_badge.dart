import 'package:flutter/material.dart';

import '../services/expiry.dart';

Color expiryColor(ExpiryLevel level, ColorScheme scheme) {
  switch (level) {
    case ExpiryLevel.expired:
    case ExpiryLevel.critical:
      return scheme.error;
    case ExpiryLevel.soon:
      return Colors.orange.shade800;
    case ExpiryLevel.none:
      return scheme.onSurfaceVariant;
  }
}

IconData expiryIcon(ExpiryLevel level) => switch (level) {
      ExpiryLevel.expired => Icons.error_outline,
      ExpiryLevel.critical => Icons.warning_amber_rounded,
      ExpiryLevel.soon => Icons.schedule,
      ExpiryLevel.none => Icons.check_circle_outline,
    };

/// Small coloured pill: "Läuft in 45 Tagen ab" / "Abgelaufen seit …".
class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge(this.info, {super.key, this.compact = false});
  final ExpiryInfo info;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!info.needsAttention) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final color = expiryColor(info.level, scheme);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(expiryIcon(info.level), size: compact ? 12 : 16, color: color),
        SizedBox(width: compact ? 4 : 6),
        Text(info.label,
            style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: color,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
