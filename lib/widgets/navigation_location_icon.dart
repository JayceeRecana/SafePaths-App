import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Cosmetic native location puck. It does not supply or modify GPS positions.
abstract final class NavigationLocationIcon {
  static final Map<IconData, Future<Uint8List>> _images = {};

  static IconData iconFor(String? mode) => switch (mode) {
    'Walking' => Icons.directions_walk,
    'Motorcycle' => Icons.motorcycle,
    'SUV / Pickup' => Icons.airport_shuttle,
    _ => Icons.directions_car,
  };

  static Future<Uint8List> image(String? mode) {
    final icon = iconFor(mode);
    return _images.putIfAbsent(icon, () async {
      try {
        return await _render(icon);
      } catch (_) {
        _images.remove(icon);
        rethrow;
      }
    });
  }

  static Future<Uint8List> _render(IconData icon) async {
    // Render at 2x and scale in Mapbox for a crisp, compact 40px marker.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(40, 42),
      37,
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawCircle(const Offset(40, 39), 36, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(40, 39),
      30,
      Paint()..color = const Color(0xFF005BBB),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 40,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(40 - painter.width / 2, 39 - painter.height / 2),
    );
    painter.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 80);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Location icon encoding failed');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
