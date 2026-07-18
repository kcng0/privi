import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/constants.dart';
import '../../core/media_thumbnail_spec.dart';
import '../../core/theme/vault_colors.dart';
import '../../domain/models/media_item.dart';
import '../common/heart_rating_bar.dart';
import '../common/video_duration_badge.dart';

/// Dense media cell + 0–3 heart bar.
///
/// Loads its poster through the shared [gridThumbnailServiceProvider] so the
/// Invisible grid uses the same cache, size, and representative frame as the
/// Visible grid.
class ThumbnailTile extends ConsumerStatefulWidget {
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
  ConsumerState<ThumbnailTile> createState() => _ThumbnailTileState();
}

class _ThumbnailTileState extends ConsumerState<ThumbnailTile> {
  ImageProvider? _provider;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.thumbnailPath != widget.item.thumbnailPath) {
      _provider = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final item = widget.item;
    try {
      final bytes = await ref
          .read(gridThumbnailServiceProvider)
          .forVaultItem(item, size: MediaThumbnailSpec.gridDimension);
      if (!mounted || item.id != widget.item.id) return;
      setState(() {
        _provider = bytes == null
            ? null
            : ResizeImage(
                MemoryImage(bytes),
                width: MediaThumbnailSpec.gridDimension,
              );
        _loading = false;
      });
    } catch (_) {
      if (mounted && item.id == widget.item.id) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Material(
      color: context.vaultColors.chrome,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'media-hero-${item.id}',
              child: _provider != null
                  ? Image(
                      image: _provider!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : _loading
                      ? ColoredBox(color: context.vaultColors.surfaceAlt)
                      : (item.isVideo
                          ? const _VideoPlaceholder()
                          : const _Broken()),
            ),
            if (item.isVideo)
              Positioned(
                top: 4,
                left: 4,
                child: VideoDurationBadge(durationMs: item.durationMs),
              ),
            // Selection overlay
            if (widget.selecting)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  widget.selected ? Icons.check_circle : Icons.circle_outlined,
                  color: widget.selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70,
                  size: 22,
                ),
              ),
            if (widget.selected)
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
                interactive: !widget.selecting && widget.onRate != null,
                onRate: widget.onRate,
              ),
            ),
          ],
        ),
      ),
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
