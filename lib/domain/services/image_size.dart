import 'dart:typed_data';
import 'dart:ui' as ui;

typedef ImageSizeReader = Future<({int width, int height})?> Function(
  List<int> bytes,
);

Future<({int width, int height})?> readImageSize(List<int> bytes) async {
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = (width: image.width, height: image.height);
    image.dispose();
    return size;
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}
