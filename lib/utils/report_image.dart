import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

const maxReportPhotoBytes = 10 * 1024 * 1024;
const maxReportPhotoPixels = 16 * 1000 * 1000;

img.Image _decodeReportPhoto(Uint8List bytes) {
  if (bytes.length > maxReportPhotoBytes) {
    throw const FormatException(
      'Please choose a JPG or PNG photo no larger than 10 MB.',
    );
  }
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;
  const pngHeader = [137, 80, 78, 71, 13, 10, 26, 10];
  final png =
      bytes.length >= 8 &&
      List.generate(8, (i) => bytes[i] == pngHeader[i]).every((v) => v);
  if (!jpeg && !png) {
    throw const FormatException(
      'Unsupported photo format. Please choose a JPG or PNG image.',
    );
  }
  try {
    final img.Decoder decoder = jpeg ? img.JpegDecoder() : img.PngDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null) {
      throw const FormatException(
        'This photo cannot be read. Please choose another JPG or PNG image.',
      );
    }
    if (info.width <= 0 ||
        info.height <= 0 ||
        info.width > 20000 ||
        info.height > 20000 ||
        info.width * info.height > maxReportPhotoPixels) {
      throw const FormatException(
        'This photo has very large dimensions. Please resize it and try again.',
      );
    }
    // Decode one frame only: animated PNGs must not allocate all frames.
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException(
        'This photo cannot be read. Please choose another JPG or PNG image.',
      );
    }
    return img.bakeOrientation(decoded);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'This photo is damaged or unreadable. Please choose another JPG or PNG image.',
    );
  }
}

img.Image _resizeWithin(img.Image image, int maxSide) {
  if (image.width <= maxSide && image.height <= maxSide) return image;
  final scale = maxSide / math.max(image.width, image.height);
  return img.copyResize(
    image,
    width: math.max(1, (image.width * scale).round()),
    height: math.max(1, (image.height * scale).round()),
  );
}

/// Validate the original encoding before watermarking and bound native decoding.
/// Run using compute so decoding does not block the interface.
Uint8List normalizeReportPhoto(Uint8List bytes) => Uint8List.fromList(
  img.encodeJpg(
    _withoutMetadata(_resizeWithin(_decodeReportPhoto(bytes), 1600)),
    quality: 85,
  ),
);

/// Final upload compression, preserving aspect ratio and avoiding upscaling.
Uint8List prepareReportImage(Uint8List bytes) => Uint8List.fromList(
  img.encodeJpg(
    _withoutMetadata(_resizeWithin(_decodeReportPhoto(bytes), 600)),
    quality: 70,
  ),
);

img.Image _withoutMetadata(img.Image image) {
  final clean = img.Image(
    width: image.width,
    height: image.height,
    numChannels: 3,
  );
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, image);
  return clean;
}

/// Fresh RGB pixels preserve orientation/aspect ratio without copying source
/// EXIF/GPS, ICC or text metadata. Run this using compute, not on the UI thread.
Uint8List preparePrivateMedia(Map<String, dynamic> input) {
  final purpose = input['purpose'];
  if (purpose != 'avatar' && purpose != 'feedback')
    throw const FormatException('Unknown image purpose.');
  final image = _resizeWithin(
    _decodeReportPhoto(input['bytes'] as Uint8List),
    purpose == 'avatar' ? 256 : 1600,
  );
  final clean = _withoutMetadata(image);
  final bytes = Uint8List.fromList(img.encodeJpg(clean, quality: 85));
  if (bytes.length > (purpose == 'avatar' ? 256 * 1024 : 2 * 1024 * 1024))
    throw const FormatException(
      'The prepared image is too large. Choose a smaller image.',
    );
  return bytes;
}

/// Bounded compatibility reader only. New uploads never store inline images.
Uint8List? boundedLegacyImage(String value) {
  if (value.length > 700000 ||
      !RegExp(r'^data:image/(jpeg|png);base64,').hasMatch(value))
    return null;
  try {
    final bytes = base64Decode(value.substring(value.indexOf(',') + 1));
    if (bytes.length > 512 * 1024) return null;
    final decoder = value.startsWith('data:image/png')
        ? img.PngDecoder()
        : img.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > 4096 ||
        info.height > 4096 ||
        info.width * info.height > 4 * 1000 * 1000)
      return null;
    return bytes;
  } catch (_) {
    return null;
  }
}
