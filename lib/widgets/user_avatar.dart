import '../utils/report_image.dart';
import 'safe_image.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final File? localFile;
  final double size;
  final double iconSize;
  final Color backgroundColor;
  final Color iconColor;

  const UserAvatar({
    super.key,
    this.photoUrl,
    this.localFile,
    this.size = 40,
    this.iconSize = 20,
    this.backgroundColor = AppColors.primaryContainer,
    this.iconColor = AppColors.onPrimaryContainer,
  });

  @override
  Widget build(BuildContext context) {
    if (localFile != null && localFile!.existsSync()) {
      return ClipOval(
        child: Image.file(
          localFile!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    if (photoUrl != null && photoUrl!.isNotEmpty) {
      final url = photoUrl!;
      if (protectedImageKind(url) == ProtectedImageKind.media) {
        return ClipOval(
          child: SafeImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorWidget: _buildFallbackIcon(),
          ),
        );
      } else if (url.startsWith('data:image')) {
        final bytes = boundedLegacyImage(url);
        if (bytes == null) return _buildFallbackIcon();
        return ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: 512,
            errorBuilder: (_, __, ___) => _buildFallbackIcon(),
          ),
        );
      } else if (url.startsWith('https://')) {
        return ClipOval(
          child: Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(),
          ),
        );
      }
    }

    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(Icons.person, size: iconSize, color: iconColor),
    );
  }
}
