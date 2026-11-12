import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class ImageWatermarkUtil {
  /// Takes a [sourceFile], burns a professional emergency watermark onto the image
  /// with [locationName], [lat], [lng], and [timestamp], then returns the new watermarked [File].
  static Future<File> applyWatermark({
    required File sourceFile,
    required String locationName,
    double? lat,
    double? lng,
    required DateTime timestamp,
    bool isLiveCamera = false,
  }) async {
    ui.Codec? codec;
    ui.Image? image;
    ui.Image? watermarkedImage;
    ui.Picture? picture;
    TextPainter? titlePainter;
    TextPainter? metaPainter;
    TextPainter? tagPainter;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      final bytes = await sourceFile.readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final resize = math.min(
        1.0,
        1600 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * resize).round()),
        targetHeight: math.max(1, (descriptor.height * resize).round()),
      );
      final frame = await codec.getNextFrame();
      image = frame.image;

      final width = image.width.toDouble();
      final height = image.height.toDouble();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      // 1. Draw Original Image
      canvas.drawImage(image, Offset.zero, Paint());

      // 2. Proportional Scaling Factors based on Image Width (baseline ~1000px)
      final scale = math.min(width / 1080.0, height / 220.0);
      final bannerPadding = 24.0 * scale;
      final bannerHeight = 160.0 * scale;
      final cornerRadius = 16.0 * scale;

      final bannerRect = Rect.fromLTWH(
        bannerPadding,
        height - bannerHeight - bannerPadding,
        width - (bannerPadding * 2),
        bannerHeight,
      );

      // 3. Draw Translucent Dark Backdrop with Rounded Corners & Subtle Border
      final bgPaint = Paint()
        ..color =
            const Color(0xE60A1128) // 90% opacity deep navy/black
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color =
            const Color(0x6648CAE4) // Subtle cyan accent border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale;

      final rrect = RRect.fromRectAndRadius(
        bannerRect,
        Radius.circular(cornerRadius),
      );

      canvas.drawRRect(rrect, bgPaint);
      canvas.drawRRect(rrect, borderPaint);

      // 4. Formatting Details
      final formattedTime = DateFormat(
        'yyyy-MM-dd • hh:mm a',
      ).format(timestamp);
      String metaText = '🕒 $formattedTime';
      if (lat != null && lng != null) {
        final latDir = lat >= 0 ? 'N' : 'S';
        final lngDir = lng >= 0 ? 'E' : 'W';
        final formattedCoords =
            '${lat.abs().toStringAsFixed(5)}° $latDir, ${lng.abs().toStringAsFixed(5)}° $lngDir';
        metaText = '🌐 $formattedCoords   •   🕒 $formattedTime';
      }

      // 5. Draw Title / Location Line
      titlePainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '📍 ',
              style: TextStyle(fontSize: 22.0 * scale),
            ),
            TextSpan(
              text: locationName.isNotEmpty
                  ? locationName
                  : 'Brgy. Marulas, Valenzuela City',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22.0 * scale,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: bannerRect.width - (32.0 * scale));

      titlePainter.paint(
        canvas,
        Offset(
          bannerRect.left + (16.0 * scale),
          bannerRect.top + (16.0 * scale),
        ),
      );

      // 6. Draw Coordinates & Timestamp Line
      metaPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: metaText,
              style: TextStyle(
                color: const Color(0xFFB0C4DE),
                fontSize: 16.0 * scale,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: bannerRect.width - (32.0 * scale));

      metaPainter.paint(
        canvas,
        Offset(
          bannerRect.left + (16.0 * scale),
          bannerRect.top + (52.0 * scale),
        ),
      );

      // 7. Draw Verification Badge Line
      final badgeLabel = isLiveCamera
          ? '🛡️ SafePaths Field Evidence • Live Camera Capture'
          : '🛡️ SafePaths Citizen Evidence • Gallery Upload';

      tagPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: badgeLabel,
              style: TextStyle(
                color: const Color(0xFF48CAE4),
                fontSize: 14.0 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: bannerRect.width - (32.0 * scale));

      tagPainter.paint(
        canvas,
        Offset(
          bannerRect.left + (16.0 * scale),
          bannerRect.top + (84.0 * scale),
        ),
      );

      // 8. Finalize and Save Image to File
      picture = recorder.endRecording();
      watermarkedImage = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await watermarkedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) return sourceFile;

      final tempDir = await getTemporaryDirectory();
      final watermarkedFile = File(
        '${tempDir.path}/watermarked_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await watermarkedFile.writeAsBytes(byteData.buffer.asUint8List());

      return watermarkedFile;
    } catch (e) {
      debugPrint('[ImageWatermarkUtil] Watermarking failed: $e');
      // If watermarking encounters any issue, gracefully return the original file
      return sourceFile;
    } finally {
      titlePainter?.dispose();
      metaPainter?.dispose();
      tagPainter?.dispose();
      watermarkedImage?.dispose();
      picture?.dispose();
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
