import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/media_thumbnail_spec.dart';
import '../../core/theme/vault_colors.dart';
import '../../domain/models/media_item.dart';
import '../common/heart_rating_bar.dart';
import '../common/video_duration_badge.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaThumbnailSpec.dimension / dpr;
        final cachePx = (logicalWidth * dpr)
            .ceil()
            .clamp(128, MediaThumbnailSpec.dimension);

        return Material(
          color: context.vaultColors.chrome,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'media-hero-${item.id}',
                  // Videos without a still can't be decoded by Image.file (mp4).
                  child: item.isVideo && !item.hasThumbnail
                      ? const _VideoPlaceholder()
                      : Image.file(
                          File(item.displayPath),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          cacheWidth: cachePx,
                          cacheHeight: cachePx,
                          errorBuilder: (_, __, ___) => item.isVideo
                              ? const _VideoPlaceholder()
                              : const _Broken(),
                        ),
                ),
                if (item.isVideo)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: VideoDurationBadge(durationMs: item.durationMs),
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
      },
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.vaultColors.surfaceAlt,
      child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.vaultColors.surfaceAlt,
      child: const Center(
        child: Icon(Icons.videocam_outlined, color: Colors.white38, size: 36),
      ),
    );
  }
}
