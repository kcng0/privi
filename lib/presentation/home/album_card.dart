import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/vault_colors.dart';
import '../../domain/enums.dart';
import '../../domain/models/album_view.dart';

/// Album mosaic tile:
/// full-bleed cover, name + count overlaid on a bottom gradient.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.view,
    required this.onTap,
  });

  final AlbumView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final album = view.album;
    final kind = album.systemKind;
    final coverPath = view.cover?.displayPath;
    final hasCover = coverPath != null && coverPath.isNotEmpty;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadii.albumTile),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover)
              Image.file(
                File(coverPath),
                fit: BoxFit.cover,
                cacheWidth: 512,
                errorBuilder: (_, __, ___) => _SystemPlaceholder(kind: kind),
              )
            else
              _SystemPlaceholder(kind: kind),
            // Bottom gradient so white label stays legible.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Row(
                children: [
                  if (kind == SystemAlbumKind.favorites) ...[
                    Icon(
                      Icons.favorite,
                      size: 12,
                      color: context.vaultColors.heart,
                    ),
                    const SizedBox(width: 3),
                  ],
                  Expanded(
                    child: Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                  _CountBadge(count: view.count),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadii.badge),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Special tiles for system albums without a cover (Favorites, empty All…).
class _SystemPlaceholder extends StatelessWidget {
  const _SystemPlaceholder({this.kind});
  final SystemAlbumKind? kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    IconData icon;
    Color iconColor;
    switch (kind) {
      case SystemAlbumKind.favorites:
        icon = Icons.favorite_border;
        iconColor = context.vaultColors.heart;
      case SystemAlbumKind.recycle:
        icon = Icons.delete_outline;
        iconColor = scheme.onSurfaceVariant;
      case SystemAlbumKind.all:
        icon = Icons.photo_library_outlined;
        iconColor = scheme.onSurfaceVariant;
      case null:
        icon = Icons.photo_album_outlined;
        iconColor = scheme.onSurfaceVariant;
    }
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(child: Icon(icon, size: 40, color: iconColor)),
    );
  }
}
