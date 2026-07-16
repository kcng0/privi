import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/security_service.dart';

/// Android-style 3×3 pattern lock. Reports completed patterns as `0-1-2-…`.
class PatternLock extends StatefulWidget {
  const PatternLock({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.error = false,
    this.size = 280,
  });

  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool error;
  final double size;

  @override
  State<PatternLock> createState() => _PatternLockState();
}

class _PatternLockState extends State<PatternLock> {
  final List<int> _cells = [];
  Offset? _finger;
  bool _reporting = false;

  static const _hitRadiusFactor = 0.38;

  List<Offset> _centers(Size size) {
    final pad = size.shortestSide * 0.12;
    final usable = size.shortestSide - pad * 2;
    final step = usable / 2;
    final origin = Offset(
      (size.width - usable) / 2,
      (size.height - usable) / 2,
    );
    return [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++)
          Offset(origin.dx + c * step, origin.dy + r * step),
    ];
  }

  int? _hitTest(Offset p, List<Offset> centers, double hitR) {
    for (var i = 0; i < centers.length; i++) {
      if ((centers[i] - p).distance <= hitR) return i;
    }
    return null;
  }

  /// Android fills intermediate dots on knight/line jumps (e.g. 0→2 adds 1).
  void _addCell(int cell) {
    if (_cells.contains(cell)) return;
    if (_cells.isNotEmpty) {
      final last = _cells.last;
      final mid = _midpoint(last, cell);
      if (mid != null && !_cells.contains(mid)) {
        _cells.add(mid);
        HapticFeedback.selectionClick();
      }
    }
    _cells.add(cell);
    HapticFeedback.selectionClick();
  }

  int? _midpoint(int a, int b) {
    final ar = a ~/ 3, ac = a % 3;
    final br = b ~/ 3, bc = b % 3;
    if ((ar - br).abs() % 2 == 0 && (ac - bc).abs() % 2 == 0) {
      final mr = (ar + br) ~/ 2;
      final mc = (ac + bc) ~/ 2;
      if ((mr == ar && mc == ac) || (mr == br && mc == bc)) return null;
      // Only if mid is exactly between (same line/diagonal).
      if ((ar - br).abs() <= 2 && (ac - bc).abs() <= 2) {
        final mid = mr * 3 + mc;
        if (mid != a && mid != b) return mid;
      }
    }
    return null;
  }

  void _onDown(Offset local, List<Offset> centers, double hitR) {
    if (!widget.enabled || _reporting) return;
    setState(() {
      _cells.clear();
      _finger = local;
      final hit = _hitTest(local, centers, hitR);
      if (hit != null) _addCell(hit);
    });
  }

  void _onMove(Offset local, List<Offset> centers, double hitR) {
    if (!widget.enabled || _reporting) return;
    setState(() {
      _finger = local;
      final hit = _hitTest(local, centers, hitR);
      if (hit != null) _addCell(hit);
    });
  }

  void _onEnd() {
    if (!widget.enabled || _reporting) return;
    final pattern = SecurityService.encodePattern(List.of(_cells));
    setState(() {
      _finger = null;
    });
    if (_cells.length < 4) {
      // Too short — clear with light feedback.
      HapticFeedback.heavyImpact();
      setState(() => _cells.clear());
      return;
    }
    _reporting = true;
    widget.onCompleted(pattern);
    // Caller clears via key or error flash; reset after brief hold.
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() {
        _cells.clear();
        _reporting = false;
      });
    });
  }

  void clear() {
    setState(() {
      _cells.clear();
      _finger = null;
      _reporting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = widget.error ? scheme.error : scheme.primary;
    final dotColor = widget.error ? scheme.error : Colors.white70;

    // Fixed square; parent is responsible for centering (Center / Align).
    return SizedBox.square(
      dimension: widget.size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final centers = _centers(size);
          final hitR = size.shortestSide / 3 * _hitRadiusFactor;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => _onDown(d.localPosition, centers, hitR),
            onPanUpdate: (d) => _onMove(d.localPosition, centers, hitR),
            onPanEnd: (_) => _onEnd(),
            onPanCancel: _onEnd,
            child: CustomPaint(
              painter: _PatternPainter(
                centers: centers,
                selected: _cells,
                finger: _finger,
                lineColor: lineColor,
                dotColor: dotColor,
                selectedDotColor: lineColor,
              ),
              size: size,
            ),
          );
        },
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.centers,
    required this.selected,
    required this.finger,
    required this.lineColor,
    required this.dotColor,
    required this.selectedDotColor,
  });

  final List<Offset> centers;
  final List<int> selected;
  final Offset? finger;
  final Color lineColor;
  final Color dotColor;
  final Color selectedDotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.85)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Lines between selected cells + trailing finger.
    if (selected.isNotEmpty) {
      final path = Path()..moveTo(centers[selected.first].dx, centers[selected.first].dy);
      for (var i = 1; i < selected.length; i++) {
        path.lineTo(centers[selected[i]].dx, centers[selected[i]].dy);
      }
      if (finger != null) {
        path.lineTo(finger!.dx, finger!.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    final outer = size.shortestSide / 3 * 0.18;
    final inner = outer * 0.45;

    for (var i = 0; i < centers.length; i++) {
      final c = centers[i];
      final isSel = selected.contains(i);
      canvas.drawCircle(
        c,
        outer,
        Paint()
          ..color = (isSel ? selectedDotColor : dotColor).withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        c,
        outer,
        Paint()
          ..color = isSel ? selectedDotColor : dotColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (isSel) {
        canvas.drawCircle(
          c,
          inner,
          Paint()..color = selectedDotColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) {
    return old.selected != selected ||
        old.finger != finger ||
        old.lineColor != lineColor ||
        old.selectedDotColor != selectedDotColor;
  }
}
