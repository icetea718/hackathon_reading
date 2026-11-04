import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> openIllustrationViewer(BuildContext context, String path) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => IllustrationViewer(path: path),
  ));
}

class IllustrationViewer extends StatefulWidget {
  const IllustrationViewer({super.key, required this.path});

  final String path;

  @override
  State<IllustrationViewer> createState() => _IllustrationViewerState();
}

class _IllustrationViewerState extends State<IllustrationViewer> {
  final _controller = TransformationController();
  Offset _doubleTapPosition = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();

  void _zoomAround(double factor, Offset focal) {
    final current = _scale;
    final target = (current * factor).clamp(1.0, 5.0);
    final applied = target / current;
    if (applied == 1) return;
    final matrix = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(applied, applied, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    _controller.value = matrix * _controller.value;
  }

  void _handleSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final factor = event.scrollDelta.dy < 0 ? 1.2 : 1 / 1.2;
    _zoomAround(factor, event.localPosition);
  }

  void _handleDoubleTap() {
    if (_scale > 1.01) {
      _controller.value = Matrix4.identity();
    } else {
      _zoomAround(2.5, _doubleTapPosition);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: const Key('illustration-viewer'),
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Listener(
                    onPointerSignal: _handleSignal,
                    child: InteractiveViewer(
                      transformationController: _controller,
                      minScale: 1,
                      maxScale: 5,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        onDoubleTapDown: (details) =>
                            _doubleTapPosition = details.localPosition,
                        onDoubleTap: _handleDoubleTap,
                        child: Image.file(
                          File(widget.path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text(
                            '无法加载插图',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  key: const Key('illustration-viewer-close'),
                  tooltip: '关闭',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _close,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
