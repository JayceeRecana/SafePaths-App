import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../utils/report_image.dart';
import 'private_media_image.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/admin_report_service.dart';

enum ProtectedImageKind { report, media }

/// Identifies private backend paths only. The protected loaders still validate
/// the active project, host, resource and signed-in account before any read.
ProtectedImageKind? protectedImageKind(String reference) {
  final uri = Uri.tryParse(reference);
  if (uri == null || uri.scheme != 'https') return null;
  final match = RegExp(
    r'^/functions/v1/(?:safepaths-main|safepaths-report-proof)/(photo|media)/',
  ).firstMatch(uri.path);
  return switch (match?.group(1)) {
    'photo' => ProtectedImageKind.report,
    'media' => ProtectedImageKind.media,
    _ => null,
  };
}

class SafeImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final String? mediaResourceId;

  const SafeImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.mediaResourceId,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildFallback(context);
    }

    Widget imageWidget;
    final url = imageUrl!.trim();

    if (protectedImageKind(url) == ProtectedImageKind.media) {
      imageWidget = PrivateMediaImage(
        reference: url,
        feedbackId: mediaResourceId,
        width: width,
        height: height,
        fit: fit,
        fallback: _buildFallback(context),
      );
    } else if (url.startsWith('data:image')) {
      final bytes = boundedLegacyImage(url);
      imageWidget = bytes == null
          ? _buildFallback(context)
          : Image.memory(
              bytes,
              width: width,
              height: height,
              fit: fit,
              cacheWidth: 1600,
              errorBuilder: (_, __, ___) => _buildFallback(context),
            );
    } else if (protectedImageKind(url) == ProtectedImageKind.report) {
      imageWidget = _ProtectedReportImage(
        reference: url,
        width: width,
        height: height,
        fit: fit,
        fallback: _buildFallback,
      );
    } else if (url.startsWith('https://')) {
      imageWidget = Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildFallback(context),
      );
    } else {
      imageWidget = _buildFallback(context);
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }

    return imageWidget;
  }

  Widget _buildFallback(BuildContext context) {
    if (errorWidget != null) return errorWidget!;
    return Container(
      width: width ?? double.infinity,
      height: height ?? 180,
      color: AppPalette.of(context).surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_rounded,
        size: 36,
        color: AppPalette.of(context).onSurfaceVariant,
      ),
    );
  }
}

class _ProtectedReportImage extends StatefulWidget {
  final String reference;
  final double? width, height;
  final BoxFit fit;
  final Widget Function(BuildContext) fallback;
  const _ProtectedReportImage({
    required this.reference,
    this.width,
    this.height,
    required this.fit,
    required this.fallback,
  });
  @override
  State<_ProtectedReportImage> createState() => _ProtectedReportImageState();
}

class _ProtectedReportImageState extends State<_ProtectedReportImage> {
  StreamSubscription<User?>? _auth;
  Future<String>? _url;
  String? _uid;
  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _url = _load();
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted && user?.uid != _uid)
        setState(() {
          _uid = user?.uid;
          _url = _load();
        });
    });
  }

  Future<String> _load() async {
    final uid = _uid;
    if (uid == null) throw StateError('Sign in to view this photo.');
    final client = AdminReportService.createClient();
    try {
      final url = await client.photoUrl(widget.reference);
      if (FirebaseAuth.instance.currentUser?.uid != uid)
        throw StateError('Account changed.');
      return url;
    } finally {
      client.close();
    }
  }

  @override
  void didUpdateWidget(covariant _ProtectedReportImage old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference) _url = _load();
  }

  @override
  void dispose() {
    unawaited(_auth?.cancel());
    super.dispose();
  }

  Widget _failure(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: ColoredBox(
      color: AppPalette.of(context).surfaceContainerLow,
      child: Center(
        child: (widget.height ?? 180) < 120
            ? IconButton(
                tooltip: tr(context, 'Retry protected photo'),
                onPressed: () => setState(() => _url = _load()),
                icon: const Icon(Icons.refresh),
              )
            : Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr(context, 'Photo could not be loaded.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppPalette.of(context).onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _url = _load()),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(tr(context, 'Retry photo')),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_uid == null || FirebaseAuth.instance.currentUser?.uid != _uid)
      return widget.fallback(context);
    return FutureBuilder<String>(
      key: ValueKey('$_uid|${widget.reference}'),
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.hasData)
          return Image.network(
            snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
            errorBuilder: (_, __, ___) => _failure(context),
          );
        if (snapshot.hasError) return _failure(context);
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
