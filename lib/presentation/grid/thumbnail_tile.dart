import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../domain/models/media_item.dart';
import '../common/heart_rating_bar.dart';

/// Dense media cell + 0–3 heart bar.
class ThumbnailTile extends StatelessWidget {
  const ThumbnailTile({
    super.key,
    required this.item,
    this.selected = false,
    this.selecting = false,
    this.onTap,
    this.onLongPress,
    this.onRate,
  });

  final MediaItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<int>? onRate;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decode near cell size; clamp so low/high DPR stay reasonable.
    final cachePx = (256 * dpr).round().clamp(128, 384);

    return Material(
      color: const Color(0xFF1B3A36),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'media-hero-${item.id}',
              child: Image.file(
                File(item.displayPath),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: cachePx,
                cacheHeight: cachePx,
                errorBuilder: (_, __, ___) => const _Broken(),
              ),
            ),
            if (item.isVideo)
              Positioned(
                top: 4,
                left: 4,
                child: _DurationBadge(durationMs: item.durationMs),
              ),
            // Selection overlay
            if (selecting)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70,
                  size: 22,
                ),
              ),
            if (selected)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2.5,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: HeartRatingBar(
                rating: item.rating,
                size: 13,
                height: GridDefaults.ratingBarHeight,
                // Enhancement: tap hearts to rate without sheet (when not selecting).
                interactive: !selecting && onRate != null,
                onRate: onRate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({this.durationMs});
  final int? durationMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow, size: 12, color: Colors.white),
          if (durationMs != null) ...[
            const SizedBox(width: 2),
            Text(
              _fmt(durationMs!),
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

  String _fmt(int ms) {
    final total = (ms / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF244842),
      child: Icon(Icons.broken_image_outlined, color: Colors.white38),
    );
  }
}
