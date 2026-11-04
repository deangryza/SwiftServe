import 'dart:typed_data';
import 'dart:ui' as ui;

/// Geometric test pattern only: no person, ID number, portrait or real document.
Future<Uint8List> syntheticIdentityImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 320, 320),
    ui.Paint()..color = const ui.Color(0xFFEEEEEE),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 160, 320),
    ui.Paint()..color = const ui.Color(0xFF222222),
  );
  final picture = recorder.endRecording(),
      image = await picture.toImage(320, 320);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return Uint8List.fromList(png!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}
