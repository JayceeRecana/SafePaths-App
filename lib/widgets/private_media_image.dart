import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/private_media_service.dart';

/// Never reuses a previous account's FutureBuilder data while a new request is
/// pending. Authentication is required for every fetch; no bearer URL is stored.
class PrivateMediaImage extends StatefulWidget {
  final String reference;
  final String? feedbackId;
  final double? width, height;
  final BoxFit fit;
  final Widget fallback;
  final String? Function()? currentUid;
  final Stream<String?>? accounts;
  final Future<Uint8List> Function(String, String?)? load;
  const PrivateMediaImage({
    super.key,
    required this.reference,
    this.feedbackId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    required this.fallback,
    this.currentUid,
    this.accounts,
    this.load,
  });
  @override
  State<PrivateMediaImage> createState() => _PrivateMediaImageState();
}

class _PrivateMediaImageState extends State<PrivateMediaImage> {
  StreamSubscription<String?>? _auth;
  String? _uid;
  Future<Uint8List>? _future;
  int _generation = 0;
  String? current() {
    if (widget.currentUid != null) return widget.currentUid!();
    final user = FirebaseAuth.instance.currentUser;
    return user != null && user.emailVerified && !user.isAnonymous
        ? user.uid
        : null;
  }

  @override
  void initState() {
    super.initState();
    _uid = current();
    _reload();
    _auth =
        (widget.accounts ??
                FirebaseAuth.instance.userChanges().map(
                  (u) => u != null && u.emailVerified && !u.isAnonymous
                      ? u.uid
                      : null,
                ))
            .listen((uid) {
              if (mounted && uid != _uid)
                setState(() {
                  _uid = uid;
                  _reload();
                });
            });
  }

  void _reload() {
    final uid = _uid, generation = ++_generation;
    if (uid == null) {
      _future = null;
      return;
    }
    _future = (() async {
      final bytes = await (widget.load != null
          ? widget.load!(widget.reference, widget.feedbackId)
          : PrivateMediaService.read(
              widget.reference,
              feedbackId: widget.feedbackId,
            ));
      if (!mounted || generation != _generation || current() != uid)
        throw StateError('Account or image changed.');
      return bytes;
    })();
  }

  @override
  void didUpdateWidget(covariant PrivateMediaImage old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference ||
        old.feedbackId != widget.feedbackId)
      _reload();
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null || current() != _uid) return widget.fallback;
    return FutureBuilder<Uint8List>(
      key: ValueKey(
        '$_uid|${widget.reference}|${widget.feedbackId}|$_generation',
      ),
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData && current() == _uid)
          return Image.memory(
            snapshot.data!,
            key: ValueKey('$_uid|${widget.reference}|$_generation'),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            cacheWidth: widget.reference.contains('/media/avatar/')
                ? 256
                : 1600,
            errorBuilder: (_, __, ___) => widget.fallback,
          );
        if (snapshot.hasError)
          return Tooltip(
            message: 'Retry image',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => setState(_reload),
                child: widget.fallback,
              ),
            ),
          );
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }
}
