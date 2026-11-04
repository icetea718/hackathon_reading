import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'companion_avatar.dart';
import 'companion_clip.dart';

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
    this.onSpeak,
    this.onSpokenLine,
    this.onOpenChat,
    this.pageTurns,
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

  /// Produces a fresh line every time the reader clicks the character.
  ///
  /// The bubble shows [_thinkingLine] right away and swaps in whatever this
  /// resolves to; when it resolves to nothing the thinking line stays.
  final Future<String?> Function()? onSpeak;

  /// Called with a finished line the moment it lands in the bubble.
  ///
  /// The host reads it out loud. The thinking line is never passed here, so a
  /// click does not make the companion clear its throat aloud before it talks.
  final ValueChanged<String>? onSpokenLine;

  /// Ticks every time the reader turns the page; the companion flinches.
  final ValueListenable<int>? pageTurns;

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

  /// Shown the instant the reader clicks, while the model is still thinking.
  static const _thinkingLine = '嗯……';

  late final AnimationController _bubble;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  final GlobalKey<CompanionAvatarState> _avatarKey =
      GlobalKey<CompanionAvatarState>();

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
    widget.pageTurns?.addListener(_handlePageTurn);
  }

  @override
  void dispose() {
    widget.pageTurns?.removeListener(_handlePageTurn);
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
    final text = await _resolve(loader);
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
    final spoken =
        line == null || line.isEmpty ? _line ?? widget.greeting : line;
    if (spoken != _thinkingLine) widget.onSpokenLine?.call(spoken);
    // A little hop, so the line lands with a body language of its own.
    _avatarKey.currentState?.cheer();
    _avatarKey.currentState?.playClip(companionWaveClip);
    _hideTimer = Timer(_lingerFor, _close);
  }

  /// The reader turned the page: the companion is startled for a moment.
  void _handlePageTurn() {
    _avatarKey.currentState?.playClip(companionSurpriseClip);
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

  Future<void> _handleAvatarTap() async {
    _greetTimer?.cancel();
    if (widget.onSpeak != null) {
      await _speak();
      return;
    }
    final openChat = widget.onOpenChat;
    if (openChat == null) {
      _toggle();
      return;
    }
    _close();
    openChat();
  }

  /// Pops the thinking line at once, then swaps in the new line.
  Future<void> _speak() async {
    final speak = widget.onSpeak;
    if (speak == null) return;
    _open(_thinkingLine);
    final line = await _resolve(speak);
    if (!mounted || line == null || line.isEmpty) return;
    setState(() => _line = line);
    widget.onSpokenLine?.call(line);
    // The reader is reading a new line, so give it a fresh six seconds.
    _hideTimer?.cancel();
    _hideTimer = Timer(_lingerFor, _close);
  }

  /// Runs [load] but never waits longer than [_loadTimeout].
  Future<String?> _resolve(Future<String?> Function() load) async {
    final completer = Completer<String?>();
    void finish(String? value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    _loadTimer?.cancel();
    _loadTimer = Timer(_loadTimeout, () => finish(null));
    unawaited(
      load().then(
        finish,
        onError: (Object _, StackTrace _) => finish(null),
      ),
    );
    final text = await completer.future;
    _loadTimer?.cancel();
    return text?.trim();
  }

  void _handleSecondaryTap() {
    _greetTimer?.cancel();
    _close();
    widget.onOpenChat?.call();
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
        KeyedSubtree(
          key: const Key('companion-avatar-tap'),
          child: CompanionAvatar(
            key: _avatarKey,
            assetPath: widget.assetPath,
            height: widget.height,
            onTap: _handleAvatarTap,
            onSecondaryTap: _handleSecondaryTap,
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
