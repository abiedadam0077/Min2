import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Converts any picked image into the 64x64 PNG that Minecraft expects for server-icon.png.
/// Returns null when the bytes are not a decodable image.
Uint8List? buildServerIcon(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null) {
    return null;
  }
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final x = (decoded.width - side) ~/ 2;
  final y = (decoded.height - side) ~/ 2;
  final cropped = img.copyCrop(decoded, x: x, y: y, width: side, height: side);
  final resized = img.copyResize(cropped, width: 64, height: 64, interpolation: img.Interpolation.average);
  return Uint8List.fromList(img.encodePng(resized));
}
