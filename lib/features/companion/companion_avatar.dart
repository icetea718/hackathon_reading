import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'companion_body.dart';
import 'companion_clip.dart';
import 'companion_fish.dart';
import 'companion_idle_sprite.dart';

/// The bundled sprite the reader shows next to the page.
const companionSprite = 'assets/companion/chibi.png';

/// `flutter test` sets this variable; the baked idle loop must stay still
/// there, otherwise every `pumpAndSettle()` in the reader tests would wait on
/// an animation that never ends.
bool get _runningInTests => Platform.environment['FLUTTER_TEST'] == 'true';

/// A small 2D character that sits beside the page while the reader is reading.
///
/// The sprite is a placeholder drawn with a [CustomPainter] until real art
/// lands; pass [assetPath] to swap in an image without touching call sites.
///
/// The body runs on springs (see [CompanionBody]), so the character reacts to
/// taps, drags and the mouse pointer instead of standing still.
class CompanionAvatar extends StatefulWidget {
  const CompanionAvatar({
    super.key,
    this.assetPath,
    required this.height,
    this.onTap,
    this.onSecondaryTap,
    this.idleMotion = true,
  });

  /// Optional image asset. When null (or when the asset fails to load) the
  /// built-in painter is used instead.
  final String? assetPath;

  /// Rendered height in logical pixels; the width follows a 3:4 ratio.
  final double height;

  /// Fired when the character is tapped or clicked (not when it is dragged).
  final VoidCallback? onTap;

  /// Fired on a right click or a long press, the way to the chat.
  final VoidCallback? onSecondaryTap;

  /// Breathing and idle nudges. Tests pass false so nothing keeps ticking.
  final bool idleMotion;

  @override
  State<CompanionAvatar> createState() => CompanionAvatarState();
}

class CompanionAvatarState extends State<CompanionAvatar>
    with SingleTickerProviderStateMixin {
  // One-shot entrance only. A repeating controller would make every
  // `pumpAndSettle()` in the reader tests time out.
  late final AnimationController _entrance;
  late final Animation<double> _scale;
  late final Animation<double> _lift;

  final GlobalKey<CompanionBodyState> _bodyKey = GlobalKey<CompanionBodyState>();
  final GlobalKey<CompanionClipStageState> _stageKey =
      GlobalKey<CompanionClipStageState>();
  final ValueNotifier<double> _motion = ValueNotifier<double>(0);
  final ValueNotifier<Offset> _look = ValueNotifier<Offset>(Offset.zero);

  /// Little hop, used when the character has something to say.
  void cheer() => _bodyKey.currentState?.cheer();

  /// Plays a one-off reaction clip; the stage falls back to the idle loop when
  /// the clip ends.
  void playClip(CompanionClip clip) => _stageKey.currentState?.play(clip);

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    final curve = CurvedAnimation(parent: _entrance, curve: Curves.easeOutBack);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(curve);
    _lift = Tween<double>(begin: 6, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic),
    );
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _motion.dispose();
    _look.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.height * 0.75, widget.height);
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _lift.value),
        child: ScaleTransition(scale: _scale, child: child),
      ),
      child: SizedBox(
        key: const Key('companion-avatar'),
        width: size.width,
        height: size.height,
        child: CompanionBody(
          key: _bodyKey,
          idleMotion: widget.idleMotion && !_runningInTests,
          onTap: widget.onTap,
          onSecondaryTap: widget.onSecondaryTap,
          onPress: () => _stageKey.currentState?.play(companionPokeClip),
          onGrabbed: () => _stageKey.currentState?.play(companionDragClip),
          onReleased: () => _stageKey.currentState?.playIdle(),
          motion: _motion,
          look: _look,
          child: widget.assetPath == companionSprite
              ? CompanionIdleSprite(animate: !_runningInTests)
              : widget.assetPath != null
              ? Image.asset(
                  widget.assetPath!,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, _, _) => _fish(context),
                )
              : CompanionClipStage(
                  key: _stageKey,
                  animate: widget.idleMotion && !_runningInTests,
                ),
        ),
      ),
    );
  }

  Widget _fish(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CompanionFish(
      motion: _motion,
      look: _look,
      bodyColor: Color.lerp(scheme.primary, Colors.white, 0.30) ?? scheme.primary,
      bellyColor: const Color(0xFFFFF4E6),
      finColor: Color.lerp(scheme.primary, Colors.white, 0.58) ?? scheme.primary,
      eyeColor: const Color(0xFF22283A),
    );
  }
}
