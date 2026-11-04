import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        PointerDownEvent,
        PointerEnterEvent,
        PointerExitEvent,
        PointerHoverEvent,
        kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Gives the companion a body: springs instead of keyframes.
///
/// The child is drawn with a squash/stretch + tilt + offset that is driven by
/// a small physics solver, so the character reacts the moment the reader
/// touches it 鈥?it squashes under a tap, stretches along a drag, flies back
/// when released and gently breathes while nobody bothers it.
///
/// [idleMotion] turns the breathing and the occasional self-nudges off, which
/// also lets the ticker sleep once everything has settled. Tests rely on that:
/// a ticker that never sleeps would keep `pumpAndSettle()` waiting forever.
class CompanionBody extends StatefulWidget {
  const CompanionBody({
    super.key,
    required this.child,
    this.idleMotion = true,
    this.onTap,
    this.onPress,
    this.onSecondaryTap,
    this.onGrabbed,
    this.onReleased,
    this.motion,
    this.look,
  });

  final Widget child;

  /// Breathing and the random idle nudges. Turn off in tests.
  final bool idleMotion;

  /// Fired on a tap or a click (not on drags).
  final VoidCallback? onTap;

  /// Fired the moment a pointer goes down, before the tap or drag resolves.
  final VoidCallback? onPress;

  /// Fired on a right click (desktop) or a long press (touch), which is how
  /// the reader asks the companion to open its chat.
  final VoidCallback? onSecondaryTap;

  final VoidCallback? onGrabbed;
  final VoidCallback? onReleased;

  /// Breathing phase, published for the artwork (the fish wags with it).
  final ValueNotifier<double>? motion;

  /// Pointer position inside the body, normalised to -1..1.
  final ValueNotifier<Offset>? look;

  @override
  State<CompanionBody> createState() => CompanionBodyState();
}

class CompanionBodyState extends State<CompanionBody>
    with SingleTickerProviderStateMixin {
  // Position spring: soft enough to overshoot once, stiff enough to come home
  // in under a second.
  static const _positionStiffness = 90.0;
  static const _positionDamping = 11.0;

  // Squash spring: snappier than the position one, that is what makes a poke
  // feel like poking jelly.
  static const _squashStiffness = 300.0;
  static const _squashDamping = 18.0;

  static const _tiltStiffness = 120.0;
  static const _tiltDamping = 10.0;

  /// How far the character may be dragged from its home, in logical pixels.
  static const _dragLimit = Offset(48, 28);

  static const _breathPeriod = Duration(milliseconds: 3200);

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  double _dx = 0;
  double _dy = 0;
  double _vx = 0;
  double _vy = 0;

  /// Vertical squash: 0 is rest, 1 is fully flattened.
  double _squash = 0;
  double _squashVelocity = 0;

  double _tilt = 0;
  double _tiltVelocity = 0;
  double _tiltTarget = 0;

  double _breathPhase = 0;
  bool _hovering = false;
  bool _dragging = false;
  bool _awake = false;
  Timer? _nudgeTimer;

  @visibleForTesting
  Offset get offset => Offset(_dx, _dy);

  @visibleForTesting
  double get squash => _squash;

  @visibleForTesting
  double get tilt => _tilt;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _wake();
    if (widget.idleMotion) _scheduleNudge();
  }

  @override
  void didUpdateWidget(CompanionBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idleMotion != widget.idleMotion) {
      if (widget.idleMotion) {
        _scheduleNudge();
        _wake();
      } else {
        _nudgeTimer?.cancel();
        _nudgeTimer = null;
        _maybeSleep();
      }
    }
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _wake() {
    if (_awake) return;
    _awake = true;
    _last = Duration.zero;
    _ticker.start();
  }

  void _maybeSleep() {
    if (!_awake || widget.idleMotion || _dragging || _hovering) return;
    final moving =
        _vx.abs() > 0.6 ||
        _vy.abs() > 0.6 ||
        _dx.abs() > 0.08 ||
        _dy.abs() > 0.08 ||
        _squashVelocity.abs() > 0.02 ||
        _squash.abs() > 0.002 ||
        _tiltVelocity.abs() > 0.01 ||
        _tilt.abs() > 0.002;
    if (moving) return;
    _awake = false;
    _ticker.stop();
    // Snap the leftovers away so a sleeping body is exactly at rest.
    setState(() {
      _dx = 0;
      _dy = 0;
      _vx = 0;
      _vy = 0;
      _squash = 0;
      _squashVelocity = 0;
      _tilt = 0;
      _tiltVelocity = 0;
      _tiltTarget = 0;
    });
  }

  void _scheduleNudge() {
    _nudgeTimer?.cancel();
    final wait = Duration(
      milliseconds: 9000 + math.Random().nextInt(6000),
    );
    _nudgeTimer = Timer(wait, () {
      if (!mounted) return;
      _nudge();
      _scheduleNudge();
    });
  }

  /// A small "huh?" wiggle, the sort of thing a bored sprite does on its own.
  void _nudge() {
    _tiltVelocity += (math.Random().nextBool() ? 1 : -1) * 0.55;
    _squashVelocity += 0.9;
    _wake();
  }

  /// Poke reaction: squash, hop a little, wobble.
  void poke() {
    _squashVelocity += 4.2;
    _vy -= 34;
    _tiltVelocity += 0.8;
    _wake();
  }

  /// Little hop, used when the companion says something.
  void cheer() {
    _vy -= 46;
    _squashVelocity += 1.6;
    _wake();
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final step = dt.clamp(0.0, 0.05);

    if (widget.idleMotion) {
      _breathPhase += step * 2 * math.pi / (_breathPeriod.inMilliseconds / 1000);
    }

    // Two substeps keep the springs stable when a frame runs long.
    for (var i = 0; i < 2; i++) {
      _integrate(step / 2);
    }

    setState(() {});
    widget.motion?.value = _breathPhase;
    _maybeSleep();
  }

  void _integrate(double dt) {
    if (!_dragging) {
      _vx += (-_positionStiffness * _dx - _positionDamping * _vx) * dt;
      _vy += (-_positionStiffness * _dy - _positionDamping * _vy) * dt;
      _dx += _vx * dt;
      _dy += _vy * dt;
    }

    _squashVelocity +=
        (-_squashStiffness * _squash - _squashDamping * _squashVelocity) * dt;
    _squash += _squashVelocity * dt;

    _tiltVelocity +=
        (-_tiltStiffness * (_tilt - _tiltTarget) - _tiltDamping * _tiltVelocity) *
        dt;
    _tilt += _tiltVelocity * dt;

    // Keep the solver from exploding if something goes very wrong.
    _squash = _squash.clamp(-0.45, 0.6);
    _tilt = _tilt.clamp(-0.5, 0.5);
  }

  void _handleTap() {
    widget.onTap?.call();
  }

  void _handlePointerDown(PointerDownEvent event) {
    // A right click is aimed at the chat, not at poking the character.
    if (event.buttons == kSecondaryMouseButton) return;
    poke();
    widget.onPress?.call();
  }

  void _handleSecondaryTap() {
    if (widget.onSecondaryTap == null) return;
    poke();
    widget.onSecondaryTap!();
  }

  void _handlePanStart(DragStartDetails _) {
    _dragging = true;
    _nudgeTimer?.cancel();
    widget.onGrabbed?.call();
    _wake();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final delta = details.delta;
    _dx = (_dx + delta.dx).clamp(-_dragLimit.dx, _dragLimit.dx);
    _dy = (_dy + delta.dy).clamp(-_dragLimit.dy, _dragLimit.dy);
    // Stretch along the drag: pulling down stretches, pulling up squashes.
    _squashVelocity -= delta.dy * 0.12;
    _tiltVelocity += delta.dx * 0.02;
    _tiltTarget = (_tilt + delta.dx * 0.01).clamp(-0.28, 0.28);
    _wake();
  }

  void _handlePanEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.velocity.pixelsPerSecond;
    _vx = (velocity.dx * 0.08).clamp(-320.0, 320.0);
    _vy = (velocity.dy * 0.08).clamp(-320.0, 320.0);
    _tiltTarget = 0;
    // Landing squash, so the come-back has some weight to it.
    _squashVelocity += 1.4;
    widget.onReleased?.call();
    _wake();
    if (widget.idleMotion) _scheduleNudge();
  }

  void _handleEnter(PointerEnterEvent event) {
    _hovering = true;
    _wake();
  }

  void _handleHover(PointerHoverEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final width = box.size.width;
    final height = box.size.height;
    if (width <= 0 || height <= 0) return;
    final relative = (event.localPosition.dx / width - 0.5).clamp(-0.5, 0.5);
    _tiltTarget = relative * 0.24;
    widget.look?.value = Offset(
      (event.localPosition.dx / width * 2 - 1).clamp(-1.0, 1.0),
      (event.localPosition.dy / height * 2 - 1).clamp(-1.0, 1.0),
    );
  }

  void _handleExit(PointerExitEvent event) {
    _hovering = false;
    _tiltTarget = 0;
    widget.look?.value = Offset.zero;
    _maybeSleep();
  }

  @override
  Widget build(BuildContext context) {
    // Breathing has to be readable at the sizes the reader actually renders
    // (120-200 px tall), so it moves a couple of pixels and rocks a little.
    final breath = widget.idleMotion ? math.sin(_breathPhase) * 0.026 : 0.0;
    final sway = widget.idleMotion ? math.sin(_breathPhase * 0.5) * 1.6 : 0.0;
    final rock = widget.idleMotion ? math.sin(_breathPhase * 0.75) * 0.018 : 0.0;
    final hoverLift = _hovering ? 0.03 : 0.0;
    final scaleX = (1 - _squash * 0.55) * (1 + hoverLift - breath * 0.35);
    final scaleY = (1 + _squash) * (1 + hoverLift + breath);

    return MouseRegion(
      onEnter: _handleEnter,
      onHover: _handleHover,
      onExit: _handleExit,
      cursor: SystemMouseCursors.click,
      child: Listener(
        // React on the press itself; a tap only resolves on release, which
        // would make the poke feel late.
        onPointerDown: _handlePointerDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onSecondaryTapDown: (_) => _handleSecondaryTap(),
          onLongPress: _handleSecondaryTap,
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: Transform.translate(
            offset: Offset(_dx + sway, _dy),
            child: Transform.rotate(
              angle: _tilt + rock,
              alignment: Alignment.bottomCenter,
              child: Transform.scale(
                scaleX: scaleX,
                scaleY: scaleY,
                alignment: Alignment.bottomCenter,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
