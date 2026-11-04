import 'dart:async';

import 'package:flutter/material.dart';

import 'companion_avatar.dart';

/// The reader-facing companion: a 2D character with a speech bubble above it.
///
/// The bubble pops in on its own shortly after mount, retracts after a few
/// seconds, and can be toggled by tapping the character.
class CompanionPresence extends StatefulWidget {
  const CompanionPresence({
    super.key,
    this.assetPath,
    this.height = 160,
    this.greeting = '读到哪儿了？',
    this.autoGreet = true,
  });

  /// Optional sprite asset, forwarded to [CompanionAvatar].
  final String? assetPath;

  /// Height of the character in logical pixels.
  final double height;

  /// Text shown in the bubble.
  final String greeting;

  /// Whether the bubble should pop up by itself shortly after mount.
  final bool autoGreet;

  @override
  State<CompanionPresence> createState() => _CompanionPresenceState();
}

class _CompanionPresenceState extends State<CompanionPresence>
    with SingleTickerProviderStateMixin {
  static const _popDuration = Duration(milliseconds: 180);
  static const _retractDuration = Duration(milliseconds: 120);
  static const _greetDelay = Duration(milliseconds: 600);
  static const _lingerFor = Duration(seconds: 6);

  late final AnimationController _bubble;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  Timer? _greetTimer;
  Timer? _hideTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _bubble = AnimationController(
      vsync: this,
      duration: _popDuration,
      reverseDuration: _retractDuration,
    );
    _scale = Tween<double>(begin: 0.6, end: 1).animate(
      CurvedAnimation(
        parent: _bubble,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );
    _opacity = CurvedAnimation(
      parent: _bubble,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    if (widget.autoGreet) {
      _greetTimer = Timer(_greetDelay, _open);
    }
  }

  @override
  void dispose() {
    _greetTimer?.cancel();
    _hideTimer?.cancel();
    _bubble.dispose();
    super.dispose();
  }

  void _open() {
    _hideTimer?.cancel();
    if (!_visible) {
      setState(() => _visible = true);
    }
    _bubble.forward();
    _hideTimer = Timer(_lingerFor, _close);
  }

  void _close() {
    _hideTimer?.cancel();
    if (!_visible) return;
    _bubble.reverse().then((_) {
      if (!mounted || _bubble.value > 0) return;
      setState(() => _visible = false);
    });
  }

  void _toggle() {
    _greetTimer?.cancel();
    if (_visible) {
      _close();
    } else {
      _open();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_visible)
          GestureDetector(
            key: const Key('companion-bubble'),
            onTap: _close,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ScaleTransition(
                key: const Key('companion-bubble-scale'),
                scale: _scale,
                alignment: Alignment.bottomRight,
                child: FadeTransition(
                  opacity: _opacity,
                  child: _BubbleCard(text: widget.greeting),
                ),
              ),
            ),
          ),
        GestureDetector(
          onTap: _toggle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: CompanionAvatar(
              assetPath: widget.assetPath,
              height: widget.height,
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleCard extends StatelessWidget {
  const _BubbleCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 64, maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Material(
            color: scheme.surfaceContainerHighest,
            elevation: 2,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 4),
            child: CustomPaint(
              size: const Size(12, 6),
              painter: _TailPainter(color: scheme.surfaceContainerHighest),
            ),
          ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => oldDelegate.color != color;
}
