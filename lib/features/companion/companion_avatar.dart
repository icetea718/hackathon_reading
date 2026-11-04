import 'package:flutter/material.dart';

/// A small 2D character that sits beside the page while the reader is reading.
///
/// The sprite is a placeholder drawn with a [CustomPainter] until real art
/// lands; pass [assetPath] to swap in an image without touching call sites.
class CompanionAvatar extends StatefulWidget {
  const CompanionAvatar({super.key, this.assetPath, required this.height});

  /// Optional image asset. When null (or when the asset fails to load) the
  /// built-in painter is used instead.
  final String? assetPath;

  /// Rendered height in logical pixels; the width follows a 3:4 ratio.
  final double height;

  @override
  State<CompanionAvatar> createState() => _CompanionAvatarState();
}

class _CompanionAvatarState extends State<CompanionAvatar>
    with SingleTickerProviderStateMixin {
  // One-shot entrance only. A repeating controller would make every
  // `pumpAndSettle()` in the reader tests time out.
  late final AnimationController _entrance;
  late final Animation<double> _scale;
  late final Animation<double> _lift;

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
        child: widget.assetPath == null
            ? _placeholder(context)
            : Image.asset(
                widget.assetPath!,
                fit: BoxFit.contain,
                errorBuilder: (context, _, __) => _placeholder(context),
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _AvatarPainter(
        body: scheme.primary,
        head: scheme.secondaryContainer,
        eye: scheme.onSecondaryContainer,
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  const _AvatarPainter({
    required this.body,
    required this.head,
    required this.eye,
  });

  final Color body;
  final Color head;
  final Color eye;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Body: rounded torso filling the lower half.
    final bodyPaint = Paint()..color = body.withValues(alpha: 0.85);
    final torso = Rect.fromLTWH(w * 0.12, h * 0.5, w * 0.76, h * 0.42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(torso, Radius.circular(h * 0.12)),
      bodyPaint,
    );

    // Head: circle overlapping the torso.
    final headPaint = Paint()..color = head;
    final center = Offset(w * 0.5, h * 0.3);
    canvas.drawCircle(center, h * 0.22, headPaint);

    // Eyes.
    final eyePaint = Paint()..color = eye;
    final eyeRadius = h * 0.03;
    canvas.drawCircle(Offset(w * 0.42, h * 0.29), eyeRadius, eyePaint);
    canvas.drawCircle(Offset(w * 0.58, h * 0.29), eyeRadius, eyePaint);
  }

  @override
  bool shouldRepaint(_AvatarPainter oldDelegate) =>
      oldDelegate.body != body ||
      oldDelegate.head != head ||
      oldDelegate.eye != eye;
}
