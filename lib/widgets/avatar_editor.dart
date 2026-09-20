import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Side of the exported avatar, in pixels. Square, because [UserAvatar]
/// clips it to a circle wherever it is shown.
const int _outputSize = 512;

/// Largest side we keep when decoding the source image. Phone cameras
/// produce far more pixels than a 512px avatar needs, and holding those
/// decoded on the web canvas is wasteful.
const int _maxSourceSide = 2400;

/// Zoom is a multiplier on "just covers the frame", so 1.0 is the tightest
/// view that still fills it.
const double _minZoom = 1.0;
const double _maxZoom = 4.0;

/// Lets the user frame [imageBytes] inside the circular avatar mask before
/// it is uploaded, and returns the cropped PNG.
///
/// Returns null if they cancel. Throws if [imageBytes] is not a decodable
/// image — callers already report upload failures, and a silent null here
/// would be indistinguishable from the user backing out.
Future<Uint8List?> showAvatarEditor(
  BuildContext context,
  Uint8List imageBytes,
) async {
  final image = await _decodeCapped(imageBytes);

  if (!context.mounted) {
    image.dispose();
    return null;
  }

  // The dialog takes ownership of the image and disposes it with its state.
  // Freeing it when this future completes would be too early: showDialog
  // returns on pop, while the route goes on painting through its exit
  // animation.
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AvatarEditorDialog(image: image),
  );
}

/// Decodes [bytes], scaling down first if the source is far larger than the
/// avatar needs.
Future<ui.Image> _decodeCapped(Uint8List bytes) async {
  final probe = await _decodeOnce(bytes);
  final longest = math.max(probe.width, probe.height);
  if (longest <= _maxSourceSide) return probe;

  final scale = _maxSourceSide / longest;
  final targetWidth = (probe.width * scale).round();
  final targetHeight = (probe.height * scale).round();
  probe.dispose();

  return _decodeOnce(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
}

/// Decodes a single frame into an image the caller owns.
///
/// A frame's image belongs to its codec and dies with it — and the codec
/// here is a local that can be collected as soon as this returns — so the
/// image has to be cloned before the codec goes away.
Future<ui.Image> _decodeOnce(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image.clone();
  frame.image.dispose();
  codec.dispose();
  return image;
}

class _AvatarEditorDialog extends StatefulWidget {
  final ui.Image image;

  const _AvatarEditorDialog({required this.image});

  @override
  State<_AvatarEditorDialog> createState() => _AvatarEditorDialogState();
}

class _AvatarEditorDialogState extends State<_AvatarEditorDialog> {
  double _zoom = _minZoom;

  /// Pan, in frame-local pixels, measured from the centred position.
  Offset _offset = Offset.zero;

  bool _isSaving = false;

  // Gesture anchors, captured at the start of each drag/pinch.
  double _startZoom = _minZoom;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  @override
  void dispose() {
    widget.image.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startZoom = _zoom;
    _startOffset = _offset;
    _startFocal = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double frameSize) {
    setState(() {
      _zoom = (_startZoom * details.scale).clamp(_minZoom, _maxZoom);
      _offset = _clamp(
        _startOffset + (details.focalPoint - _startFocal),
        frameSize,
      );
    });
  }

  void _setZoom(double zoom, double frameSize) {
    setState(() {
      _zoom = zoom;
      // Re-clamp: zooming out can leave the image no longer covering the
      // frame at the current pan.
      _offset = _clamp(_offset, frameSize);
    });
  }

  /// Keeps the image covering the frame, so the crop can never include
  /// empty space.
  Offset _clamp(Offset offset, double frameSize) {
    final scale = _coverScale(frameSize) * _zoom;
    final maxDx = math.max(0.0, (widget.image.width * scale - frameSize) / 2);
    final maxDy = math.max(0.0, (widget.image.height * scale - frameSize) / 2);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx),
      offset.dy.clamp(-maxDy, maxDy),
    );
  }

  double _coverScale(double frameSize) =>
      frameSize / math.min(widget.image.width, widget.image.height);

  Future<void> _save(double frameSize) async {
    setState(() => _isSaving = true);
    try {
      final bytes = await _renderCrop(
        image: widget.image,
        // The pan was measured in frame pixels; the export is a different
        // size, so scale it across.
        offset: _offset * (_outputSize / frameSize),
        zoom: _zoom,
      );
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Fit the frame to the smaller screen dimension, leaving room for the
    // dialog's own chrome.
    final frameSize = math.min(
      320.0,
      math.min(screen.width - 96, screen.height - 340),
    ).clamp(180.0, 320.0);

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Adjust your photo',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Drag to reposition and zoom to fit. Everything inside '
                    'the circle becomes your picture.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppTheme.slate500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Center(
              child: GestureDetector(
                key: const ValueKey('avatar-editor-frame'),
                // A CustomPaint with no child does not hit-test, so without
                // this the frame never receives the drag.
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: (d) => _onScaleUpdate(d, frameSize),
                child: SizedBox(
                  width: frameSize,
                  height: frameSize,
                  child: CustomPaint(
                    painter: _AvatarFramePainter(
                      image: widget.image,
                      zoom: _zoom,
                      offset: _offset,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Icon(
                    Icons.image_outlined,
                    size: 17,
                    color: AppTheme.slate400,
                  ),
                  Expanded(
                    child: Slider(
                      value: _zoom,
                      min: _minZoom,
                      max: _maxZoom,
                      activeColor: AppTheme.maroon,
                      inactiveColor: AppTheme.slate200,
                      // A slider as well as pinch: on desktop there is no
                      // pinch gesture with a mouse.
                      onChanged: _isSaving
                          ? null
                          : (v) => _setZoom(v, frameSize),
                    ),
                  ),
                  const Icon(
                    Icons.image,
                    size: 22,
                    color: AppTheme.slate400,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : () => _save(frameSize),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                        : const Text('Use photo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the image under a circular cut-out, so the user sees exactly the
/// region that will be kept.
class _AvatarFramePainter extends CustomPainter {
  final ui.Image image;
  final double zoom;
  final Offset offset;

  _AvatarFramePainter({
    required this.image,
    required this.zoom,
    required this.offset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    _paintImage(canvas, image, size.width, zoom, offset);

    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);

    // Scrim everything outside the circle.
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawPath(scrim, Paint()..color = Colors.white.withValues(alpha: 0.72));

    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppTheme.maroon.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_AvatarFramePainter old) =>
      old.image != image || old.zoom != zoom || old.offset != offset;
}

/// The single definition of how the crop is laid out, shared by the preview
/// and the export so what the user frames is what they get.
void _paintImage(
  Canvas canvas,
  ui.Image image,
  double frameSize,
  double zoom,
  Offset offset,
) {
  final scale =
      (frameSize / math.min(image.width, image.height)) * zoom;
  final dst = Rect.fromCenter(
    center: Offset(frameSize / 2 + offset.dx, frameSize / 2 + offset.dy),
    width: image.width * scale,
    height: image.height * scale,
  );
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    dst,
    Paint()..filterQuality = FilterQuality.high,
  );
}

Future<Uint8List> _renderCrop({
  required ui.Image image,
  required Offset offset,
  required double zoom,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final side = _outputSize.toDouble();

  // Opaque backing: a transparent PNG would show through as black in some
  // image viewers, and the avatar is always shown on a filled circle.
  canvas.drawRect(
    Rect.fromLTWH(0, 0, side, side),
    Paint()..color = Colors.white,
  );
  _paintImage(canvas, image, side, zoom, offset);

  final picture = recorder.endRecording();
  try {
    final rendered = await picture.toImage(_outputSize, _outputSize);
    try {
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Could not encode the cropped image.');
      }
      return data.buffer.asUint8List();
    } finally {
      rendered.dispose();
    }
  } finally {
    picture.dispose();
  }
}
