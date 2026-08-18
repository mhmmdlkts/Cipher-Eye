import 'package:flutter/material.dart';

/// A sensitive value as a tappable row: tap copies it, long-press optionally
/// reveals it. Used by every detail screen so the interaction is uniform.
class CopyRow extends StatelessWidget {
  const CopyRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.mono = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.only(
              left: 16, right: trailing == null ? 16 : 4, top: 10, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: TextStyle(
                            fontSize: 16, letterSpacing: mono ? 1.2 : 0)),
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.content_copy,
                      size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
