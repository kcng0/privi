import 'package:flutter/material.dart';

import '../../core/theme/vault_colors.dart';

/// Shared video marker for every media grid.
class VideoDurationBadge extends StatelessWidget {
  const VideoDurationBadge({super.key, this.durationMs});

  final int? durationMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: context.vaultColors.scrim,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow, size: 12, color: Colors.white),
          if (durationMs case final duration?) ...[
            const SizedBox(width: 2),
            Text(
              _formatDuration(duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final totalSeconds = (milliseconds / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
