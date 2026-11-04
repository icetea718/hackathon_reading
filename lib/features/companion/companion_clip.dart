import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// A short animation baked from the companion's motion library.
///
/// Every clip is a sheet with [companionClipColumns] columns; the frames read
/// left to right, top to bottom, and each cell is [companionClipCell] big.
@immutable
class CompanionClip {
  const CompanionClip({
    required this.asset,
    required this.frameCount,
    required this.fps,
    this.loop = false,
  });

  final String asset;
  final int frameCount;
  final double fps;
  final bool loop;
}

const int companionClipColumns = 8;
const Size companionClipCell = Size(150, 200);

/// Breathing, blinking idle loop.
const CompanionClip companionIdleClip = CompanionClip(
  asset: 'assets/companion/pet_idle.png',
  frameCount: 36,
  fps: 12,
  loop: true,
);

/// Reaction played when the reader pokes the companion.
const CompanionClip companionPokeClip = CompanionClip(
  asset: 'assets/companion/pet_poke.png',
  frameCount: 48,
  fps: 12,
);

/// Reaction played while the companion is being dragged around.
const CompanionClip companionDragClip = CompanionClip(
  asset: 'assets/companion/pet_drag.png',
  frameCount: 48,
  fps: 12,
);

/// Plays [CompanionClip]s in place of a static sprite.
///
/// The stage starts on [companionIdleClip] and returns to it whenever a
/// one-shot clip runs out, which keeps the companion alive without any extra
/// choreography in the caller.
class CompanionClipStage extends StatefulWidget {
  const CompanionClipStage({super.key, this.animate = true});

  /// Tests pass false so the stage stays on one frame and never keeps a frame
  /// callback pending.
  final bool animate;

  @override
  State<CompanionClipStage> createState() => CompanionClipStageState();
}

class CompanionClipStageState extends State<CompanionClipStage>
    with SingleTickerProviderStateMixin {
  final Map<String, ui.Image> _sheets = {};
  late final Ticker _ticker;
  CompanionClip _clip = companionIdleClip;
  ui.Image? _sheet;
  int _frame = 0;

  /// Frame currently on screen; exposed for tests and debugging.
  @visibleForTesting
  int get frame => _frame;

  @visibleForTesting
  CompanionClip get clip => _clip;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    unawaited(_load(_clip));
    if (widget.animate) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(CompanionClipStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Switches to [clip] from its first frame.
  void play(CompanionClip clip) {
    if (identical(clip, _clip)) return;
    _clip = clip;
    _frame = 0;
    if (mounted) {
      setState(() {});
    }
    unawaited(_load(clip));
    if (widget.animate && !_ticker.isActive) {
      _ticker.start();
    }
  }

  /// Convenience for the physics layer: fall back to the breathing loop.
  void playIdle() => play(companionIdleClip);

  Future<void> _load(CompanionClip clip) async {
    final cached = _sheets[clip.asset];
    if (cached != null) {
      if (mounted && identical(clip, _clip)) {
        setState(() => _sheet = cached);
      }
      return;
    }
    final data = await rootBundle.load(clip.asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    _sheets[clip.asset] = frame.image;
    if (!mounted || !identical(clip, _clip)) return;
    setState(() => _sheet = frame.image);
  }

  void _onTick(Duration elapsed) {
    // Ticker reports time since start(), so there is no epoch to track.
    final seconds = elapsed.inMicroseconds / 1e6;
    final frame = (seconds * _clip.fps).floor();
    if (frame >= _clip.frameCount) {
      if (_clip.loop) {
        if (frame != _frame && mounted) {
          setState(() => _frame = frame % _clip.frameCount);
        }
        return;
      }
      _ticker.stop();
      if (mounted) {
        setState(() => _frame = _clip.frameCount - 1);
      }
      playIdle();
      return;
    }
    if (frame != _frame && mounted) {
      setState(() => _frame = frame);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ClipPainter(
          sheet: sheet,
          clip: _clip,
          frame: _frame,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ClipPainter extends CustomPainter {
  _ClipPainter({required this.sheet, required this.clip, required this.frame});

  final ui.Image? sheet;
  final CompanionClip clip;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    final image = sheet;
    if (image == null) return;

    final column = frame % companionClipColumns;
    final row = frame ~/ companionClipColumns;
    final source = Rect.fromLTWH(
      column * companionClipCell.width,
      row * companionClipCell.height,
      companionClipCell.width,
      companionClipCell.height,
    );

    // Contain the cell in the box, feet on the bottom edge.
    final scale = (size.width / source.width) < (size.height / source.height)
        ? size.width / source.width
        : size.height / source.height;
    final width = source.width * scale;
    final height = source.height * scale;
    final destination = Rect.fromLTWH(
      (size.width - width) / 2,
      size.height - height,
      width,
      height,
    );

    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ClipPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.clip != clip ||
      oldDelegate.sheet != sheet;
}
