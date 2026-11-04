import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A baked idle loop for the companion: 62 frames of a Live2D model laid out
/// in an 8-column grid, played back at 20 fps.
///
/// The frames are rendered once, off-device, by the Cubism runtime (see
/// `.superpowers/spikes/live2d/`); the app only blits them, so no plugin and no
/// animation library is needed and the loop behaves the same on every platform.
const companionIdleSheet = 'assets/companion/chibi_idle.png';

/// Number of frames stored in [companionIdleSheet].
const companionIdleFrameCount = 62;

/// Grid width of [companionIdleSheet]; the height follows from the frame count.
const companionIdleColumns = 8;

/// Size of a single frame inside [companionIdleSheet].
const companionIdleFrameSize = Size(169, 384);

/// Playback rate of [companionIdleSheet]; the whole sheet lasts ~3.1 s.
const companionIdleFps = 20.0;

/// Plays the baked idle loop, scaled to fit the box it is given.
///
/// The sheet is decoded once and blitted frame by frame with a
/// [CustomPainter], so there is no per-frame widget rebuild of the subtree.
class CompanionIdleSprite extends StatefulWidget {
  const CompanionIdleSprite({super.key, this.animate = true});

  /// When false only the first frame is painted. Tests pass false so that
  /// `pumpAndSettle` never waits on a looping animation.
  final bool animate;

  @override
  CompanionIdleSpriteState createState() => CompanionIdleSpriteState();
}

class CompanionIdleSpriteState extends State<CompanionIdleSprite>
    with SingleTickerProviderStateMixin {
  ui.Image? _sheet;
  Ticker? _ticker;
  int _frame = 0;

  /// Index of the frame currently painted; exposed for tests.
  @visibleForTesting
  int get frameIndex => _frame;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.animate) {
      _ticker = createTicker(_tick)..start();
    }
  }

  Future<void> _load() async {
    try {
      final data = await rootBundle.load(companionIdleSheet);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _sheet = frame.image);
    } catch (_) {
      // A missing sheet just leaves the box empty; the caller still has the
      // static sprite as a fallback layer if it wants one.
    }
  }

  void _tick(Duration elapsed) {
    final next =
        (elapsed.inMicroseconds * companionIdleFps ~/ 1000000) %
        companionIdleFrameCount;
    if (next != _frame) {
      setState(() => _frame = next);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sheet?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    if (sheet == null) {
      return const SizedBox.expand();
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _SheetPainter(sheet: sheet, frame: _frame),
    );
  }
}

class _SheetPainter extends CustomPainter {
  const _SheetPainter({required this.sheet, required this.frame});

  final ui.Image sheet;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final column = frame % companionIdleColumns;
    final row = frame ~/ companionIdleColumns;
    final src = Rect.fromLTWH(
      column * companionIdleFrameSize.width,
      row * companionIdleFrameSize.height,
      companionIdleFrameSize.width,
      companionIdleFrameSize.height,
    );

    // Contain the frame in the box, anchored to the bottom so the character
    // keeps its feet on the same line whatever the box size.
    final scale = (size.width / src.width) < (size.height / src.height)
        ? size.width / src.width
        : size.height / src.height;
    final dstWidth = src.width * scale;
    final dstHeight = src.height * scale;
    final dst = Rect.fromLTWH(
      (size.width - dstWidth) / 2,
      size.height - dstHeight,
      dstWidth,
      dstHeight,
    );

    canvas.drawImageRect(
      sheet,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SheetPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.sheet != sheet;
}
