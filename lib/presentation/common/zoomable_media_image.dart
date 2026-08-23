import 'dart:io';

import 'package:flutter/material.dart';

/// Image that yields one-finger horizontal drags to a parent [PageView].
///
/// Pinch/pan zoom is available after double-tap so [InteractiveViewer] does
/// not steal folder swipe navigation at the default scale.
class ZoomableMediaImage extends StatefulWidget {
  const ZoomableMediaImage({
    super.key,
    required this.file,
    this.heroTag,
    this.onTap,
    this.onZoomChanged,
    this.fit = BoxFit.contain,
  });

  final File file;
  final Object? heroTag;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onZoomChanged;
  final BoxFit fit;

  static const zoomScale = 2.5;

  @override
  State<ZoomableMediaImage> createState() => _ZoomableMediaImageState();
}

class _ZoomableMediaImageState extends State<ZoomableMediaImage> {
  final _transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    if (!_zoomed) return;
    if (_transform.value.getMaxScaleOnAxis() > 1.05) return;
    _zoomed = false;
    _transform.value = Matrix4.identity();
    widget.onZoomChanged?.call(false);
    if (mounted) setState(() {});
  }

  void _toggleZoom() {
    if (_zoomed) {
      _zoomed = false;
      _transform.value = Matrix4.identity();
    } else {
      _zoomed = true;
      _transform.value = Matrix4.identity()
        ..scaleByDouble(
          ZoomableMediaImage.zoomScale,
          ZoomableMediaImage.zoomScale,
          ZoomableMediaImage.zoomScale,
          1,
        );
    }
    widget.onZoomChanged?.call(_zoomed);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Widget image = Image.file(widget.file, fit: widget.fit);
    final heroTag = widget.heroTag;
    if (heroTag != null) {
      image = Hero(tag: heroTag, child: image);
    }
    image = Center(child: image);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: _toggleZoom,
      child: _zoomed
          ? InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 4,
              child: image,
            )
          : image,
    );
  }
}
