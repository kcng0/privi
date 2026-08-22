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
    this.fit = BoxFit.contain,
  });

  final File file;
  final Object? heroTag;
  final VoidCallback? onTap;
  final BoxFit fit;

  @override
  State<ZoomableMediaImage> createState() => _ZoomableMediaImageState();
}

class _ZoomableMediaImageState extends State<ZoomableMediaImage> {
  final _transform = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    setState(() {
      _zoomed = !_zoomed;
      if (!_zoomed) _transform.value = Matrix4.identity();
    });
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
              child: image,
            )
          : image,
    );
  }
}
