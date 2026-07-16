import 'package:flutter/material.dart';
import '../../core/l10n.dart';

import '../../core/theme/vault_colors.dart';

/// Always-three-slot heart bar with optional pop animation.
class HeartRatingBar extends StatefulWidget {
  const HeartRatingBar({
    super.key,
    required this.rating,
    this.size = 14,
    this.interactive = false,
    this.onRate,
    this.scrim = true,
    this.height = 22,
  });

  final int rating;
  final double size;
  final bool interactive;
  final ValueChanged<int>? onRate;
  final bool scrim;
  final double height;

  @override
  State<HeartRatingBar> createState() => _HeartRatingBarState();
}

class _HeartRatingBarState extends State<HeartRatingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  int _lastRating = 0;

  @override
  void initState() {
    super.initState();
    _lastRating = widget.rating;
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0.85,
      upperBound: 1.2,
    );
  }

  @override
  void didUpdateWidget(covariant HeartRatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rating != _lastRating) {
      _lastRating = widget.rating;
      _pop.forward(from: 0.85).then((_) {
        if (mounted) _pop.reverse();
      });
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = context.vaultColors;
    final clamped = widget.rating.clamp(0, 3);

    Widget row = AnimatedBuilder(
      animation: _pop,
      builder: (context, child) {
        final scale = _pop.isAnimating ? _pop.value : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final filled = i < clamped;
          final heart = Icon(
            filled ? Icons.favorite : Icons.favorite_border,
            size: widget.size,
            color: filled ? vc.heart : vc.heartOutline,
          );
          if (!widget.interactive) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: heart,
            );
          }
          return InkWell(
            onTap: () {
              final next = i + 1;
              if (clamped == next) {
                widget.onRate?.call(0);
              } else {
                widget.onRate?.call(next);
              }
            },
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: heart,
            ),
          );
        }),
      ),
    );

    row = Semantics(
      label: context.l10n.ratedHearts(clamped),
      child: row,
    );

    if (!widget.scrim) return row;

    return Container(
      height: widget.height,
      width: double.infinity,
      color: vc.scrim,
      alignment: Alignment.center,
      child: row,
    );
  }
}
