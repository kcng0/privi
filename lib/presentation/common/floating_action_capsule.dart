import 'package:flutter/material.dart';

/// Floating horizontal pill menu (bottom-center).
class FloatingActionItem {
  const FloatingActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

/// Rounded capsule centered above the bottom safe area.
class FloatingActionCapsule extends StatelessWidget {
  const FloatingActionCapsule({
    super.key,
    required this.actions,
    this.onDismiss,
  });

  final List<FloatingActionItem> actions;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: const Color(0xE61B3A36),
            elevation: 12,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: Colors.white12,
                      ),
                    _CapsuleButton(item: actions[i]),
                  ],
                  if (onDismiss != null) ...[
                    Container(
                      width: 1,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      color: Colors.white12,
                    ),
                    _CapsuleButton(
                      item: FloatingActionItem(
                        icon: Icons.close,
                        label: 'Close',
                        onTap: onDismiss!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({required this.item});
  final FloatingActionItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.destructive
        ? const Color(0xFFFF8A80)
        : Colors.white.withValues(alpha: 0.92);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Show a bottom sheet of secondary actions (More ▾).
Future<void> showMoreActionsSheet(
  BuildContext context, {
  required List<FloatingActionItem> actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1B3A36),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          for (final a in actions)
            ListTile(
              leading: Icon(
                a.icon,
                color: a.destructive
                    ? const Color(0xFFFF8A80)
                    : Colors.white70,
              ),
              title: Text(
                a.label,
                style: TextStyle(
                  color: a.destructive
                      ? const Color(0xFFFF8A80)
                      : Colors.white,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                a.onTap();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
