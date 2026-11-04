import 'dart:async';

import 'package:flutter/material.dart';

import 'companion_avatar.dart';

/// The reader-facing companion: a 2D character with a speech bubble above it.
///
/// The bubble pops in on its own shortly after mount, retracts after a few
/// seconds, and can be dismissed or opened by tapping the character.
class CompanionPresence extends StatefulWidget {
  const CompanionPresence({
    super.key,
    this.assetPath,
    this.height = 160,
    this.greeting = '读到哪儿了？',
    this.autoGreet = true,
    this.greetingLoader,
    this.onOpenChat,
  });

  /// Optional sprite asset, forwarded to [CompanionAvatar].
  final String? assetPath;

  /// Height of the character in logical pixels.
  final double height;

  /// Fallback text, used when [greetingLoader] has nothing to say.
  final String greeting;

  /// Whether the bubble should pop up by itself shortly after mount.
  final bool autoGreet;

  /// Loads the line the companion says about the page being read.
  ///
  /// When it resolves to nothing the bubble falls back to [greeting]; when it
  /// takes longer than [_loadTimeout] the fallback is used instead.
  final Future<String?> Function()? greetingLoader;

  /// Opens the companion chat; when null, tapping the character toggles the
  /// bubble instead.
  final VoidCallback? onOpenChat;

  @override
  State<CompanionPresence> createState() => _CompanionPresenceState();
}

class _CompanionPresenceState extends State<CompanionPresence>
    with SingleTickerProviderStateMixin {
  static const _popDuration = Duration(milliseconds: 180);
  static const _retractDuration = Duration(milliseconds: 120);
  static const _greetDelay = Duration(milliseconds: 600);
  static const _loadTimeout = Duration(seconds: 3);
  static const _lingerFor = Duration(seconds: 6);

  late final AnimationController _bubble;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  Timer? _greetTimer;
  Timer? _hideTimer;
  Timer? _loadTimer;
  bool _visible = false;
  String? _line;

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
      _greetTimer = Timer(_greetDelay, _startGreeting);
    }
  }

  @override
  void dispose() {
    _greetTimer?.cancel();
    _hideTimer?.cancel();
    _loadTimer?.cancel();
    _bubble.dispose();
    super.dispose();
  }

  /// Asks the loader for a line, then pops the bubble with whatever it got.
  Future<void> _startGreeting() async {
    final loader = widget.greetingLoader;
    if (loader == null) {
      _open();
      return;
    }
    final completer = Completer<String?>();
    void finish(String? value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    _loadTimer?.cancel();
    _loadTimer = Timer(_loadTimeout, () => finish(null));
    unawaited(
      loader().then(
        finish,
        onError: (Object _, StackTrace _) => finish(null),
      ),
    );
    final text = await completer.future;
    _loadTimer?.cancel();
    if (!mounted) return;
    _open(text);
  }

  void _open([String? text]) {
    _hideTimer?.cancel();
    final line = text?.trim();
    setState(() {
      if (line != null && line.isNotEmpty) _line = line;
      _visible = true;
    });
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

  void _handleAvatarTap() {
    _greetTimer?.cancel();
    final openChat = widget.onOpenChat;
    if (openChat == null) {
      _toggle();
      return;
    }
    _close();
    openChat();
  }

  void _handleBubbleTap() {
    final openChat = widget.onOpenChat;
    if (openChat == null) {
      _close();
      return;
    }
    _close();
    openChat();
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
            onTap: _handleBubbleTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ScaleTransition(
                key: const Key('companion-bubble-scale'),
                scale: _scale,
                alignment: Alignment.bottomRight,
                child: FadeTransition(
                  opacity: _opacity,
                  child: _BubbleCard(text: _line ?? widget.greeting),
                ),
              ),
            ),
          ),
        GestureDetector(
          key: const Key('companion-avatar-tap'),
          onTap: _handleAvatarTap,
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
