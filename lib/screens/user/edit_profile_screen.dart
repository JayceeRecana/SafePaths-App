import '../../services/spark_proof_client.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'dart:io';
import '../../config/app_environment.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../utils/report_image.dart';
import '../../services/private_media_service.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/user_avatar.dart';
import '../../services/app_state_service.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _locationController;
  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  String? _photoUrl;
  Uint8List? _photoBytes;
  final _media = PrivateMediaUploader();
  StreamSubscription<User?>? _auth;
  Map<String, dynamic>? _context;
  bool _contextLoading = false, _photoPending = false;
  String _photoMode = 'keep';
  String? _error;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _emailController = TextEditingController(
      text: Firebase.apps.isNotEmpty
          ? FirebaseAuth.instance.currentUser?.email ?? widget.user.email
          : widget.user.email,
    );
    _locationController = TextEditingController(text: widget.user.location);
    _photoUrl = widget.user.photoUrl;
    if (AppEnvironment.sparkMediaEnabled) _loadContext();
    if (Firebase.apps.isNotEmpty)
      _auth = FirebaseAuth.instance.userChanges().listen((user) {
        if (mounted && user?.uid != widget.user.id) {
          _media.dispose();
          setState(() {
            _context = null;
            _photoBytes = null;
            _photoUrl = null;
            _photoPending = false;
            _nameController.clear();
            _emailController.clear();
            _locationController.clear();
            _error =
                'Account changed. Reopen the profile for the signed-in account.';
          });
        }
      });
  }

  @override
  void dispose() {
    _media.dispose();
    unawaited(_auth?.cancel());
    _nameController.dispose();
    _emailController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _busy => _isLoading || _isUploadingPhoto || _contextLoading;
  bool _sameAccount() =>
      Firebase.apps.isNotEmpty &&
      FirebaseAuth.instance.currentUser?.uid == widget.user.id;
  Future<void> _loadContext() async {
    setState(() {
      _contextLoading = true;
      _error = null;
    });
    try {
      if (!_sameAccount()) throw StateError('Account changed.');
      final value = await PrivateMediaService.profileContext();
      if (!mounted || !_sameAccount()) return;
      setState(() {
        if (_context == null) {
          _nameController.text = value['name'] as String;
          _locationController.text = value['location'] as String;
          _photoUrl = value['photoUrl'] as String?;
        }
        _context = value;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The profile could not be refreshed. Keep your details and retry.',
        );
    } finally {
      if (mounted) setState(() => _contextLoading = false);
    }
  }

  Future<void> _ensurePhoto() async {
    if (!_photoPending) return;
    final bytes = _photoBytes;
    if (bytes == null) throw StateError('Choose a readable photo.');
    if (!_sameAccount()) throw StateError('Account changed.');
    final uid = widget.user.id;
    String reference;
    if (AppEnvironment.sparkMediaEnabled)
      reference = await _media.upload('avatar', uid, bytes);
    else {
      // Compatibility path until the coordinated main rollout. Failure is an
      // error, never a public URL or an inline image masquerading as an upload.
      final ref = FirebaseStorage.instance.ref().child(
        'avatars/$uid/${sha256.convert(bytes)}.jpg',
      );
      await ref
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(const Duration(seconds: 45));
      reference = await ref.getDownloadURL();
    }
    if (!mounted || !_sameAccount()) throw StateError('Account changed.');
    _photoUrl = reference;
    _photoMode = 'set';
    _photoPending = false;
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    if (_busy || !AppEnvironment.profilePhotosEnabled) return;
    if (!_sameAccount()) {
      setState(() => _error = 'Sign in with this profile account.');
      return;
    }
    setState(() {
      _isUploadingPhoto = true;
      _error = null;
    });
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (picked == null || !_sameAccount()) return;
      if (mounted)
        setState(() {
          _photoPending = true;
          _photoBytes = null;
        });
      final file = File(picked.path);
      if (await file.length() > maxReportPhotoBytes)
        throw const FormatException('Choose an image no larger than 10 MB.');
      final bytes = await compute(preparePrivateMedia, {
        'purpose': 'avatar',
        'bytes': await file.readAsBytes(),
      });
      if (!mounted || !_sameAccount()) return;
      setState(() {
        _photoBytes = bytes;
        _photoPending = true;
      });
      await _ensurePhoto();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo ready. Save details to apply it.'),
          ),
        );
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is SparkProofException
              ? e.message
              : 'The photo was not confirmed. Save to retry, choose another image, or use the default avatar.',
        );
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.of(
                    context,
                  ).outlineVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr(context, 'Change Profile Photo'),
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.of(context).onSurface,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppPalette.of(
                      context,
                    ).primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: AppPalette.of(context).primary,
                  ),
                ),
                title: Text(
                  tr(context, 'Take Photo'),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AppPalette.of(context).onSurface,
                  ),
                ),
                subtitle: Text(
                  tr(context, 'Capture a new photo with camera'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppPalette.of(context).onSurfaceVariant,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadPhoto(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppPalette.of(
                      context,
                    ).secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.photo_library_rounded,
                    color: AppPalette.of(context).secondary,
                  ),
                ),
                title: Text(
                  tr(context, 'Choose from Gallery'),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AppPalette.of(context).onSurface,
                  ),
                ),
                subtitle: Text(
                  tr(context, 'Select an existing photo from gallery'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppPalette.of(context).onSurfaceVariant,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadPhoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveDetails() async {
    if (_busy) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (!_sameAccount()) throw StateError('Account changed.');
      await _ensurePhoto();
      if (!_sameAccount()) throw StateError('Account changed.');
      if (AppEnvironment.sparkMediaEnabled) {
        if (_context == null)
          throw StateError('Refresh the current profile first.');
        await PrivateMediaService.saveProfile({
          'contextToken': _context!['token'],
          'name': _nameController.text.trim(),
          'location': _locationController.text.trim(),
          'photoMode': _photoMode,
          if (_photoMode == 'set') 'photoUrl': _photoUrl,
        });
      } else {
        final data = <String, dynamic>{
          'name': _nameController.text.trim(),
          'location': _locationController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (_photoMode == 'set') 'photoUrl': _photoUrl,
          if (_photoMode == 'remove') 'photoUrl': null,
        };
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.user.id)
            .set(data, SetOptions(merge: true))
            .timeout(const Duration(seconds: 15));
      }
      if (!mounted || !_sameAccount()) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile details saved.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (e is SparkProofException && e.code == 'media-unavailable') {
        _media.forget();
        _photoPending = _photoBytes != null;
      }
      if (mounted)
        setState(
          () => _error = e is SparkProofException
              ? e.message
              : 'The profile save was not confirmed. Keep your details and retry, or refresh if it changed.',
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AbsorbPointer(
        absorbing: _busy,
        child: Scaffold(
          appBar: AppTopBar(
            title: tr(context, 'Edit Details'),
            showBackButton: true,
            showProfile: false,
            showSettingsAction: false,
            onBackPressed: () => Navigator.of(context).pop(),
          ),
          backgroundColor: AppPalette.of(context).surface,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (AppEnvironment.sparkMediaEnabled)
                    TextButton(
                      onPressed: _loadContext,
                      child: const Text('Refresh current profile'),
                    ),
                ],
                // Avatar with camera edit badge
                Center(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap:
                            _isUploadingPhoto ||
                                !AppEnvironment.profilePhotosEnabled
                            ? null
                            : _showPhotoOptions,
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppPalette.of(context).primaryContainer,
                            border: Border.all(
                              color: AppPalette.of(context).onPrimaryContainer,
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: _isUploadingPhoto
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                )
                              : _photoBytes != null
                              ? ClipOval(
                                  child: Image.memory(
                                    _photoBytes!,
                                    width: 104,
                                    height: 104,
                                    fit: BoxFit.cover,
                                    cacheWidth: 256,
                                  ),
                                )
                              : UserAvatar(
                                  photoUrl: _photoUrl,
                                  size: 104,
                                  iconSize: 52,
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap:
                              _isUploadingPhoto ||
                                  !AppEnvironment.profilePhotosEnabled
                              ? null
                              : _showPhotoOptions,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppPalette.of(context).primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppPalette.of(context).onPrimary,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppPalette.of(
                                    context,
                                  ).primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: AppPalette.of(context).onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_context?['legacyPhoto'] == true &&
                    _photoMode == 'keep' &&
                    _photoBytes == null)
                  const Text(
                    'Your existing photo is kept. Choose a new one to replace it.',
                  ),
                if (AppEnvironment.profilePhotosEnabled && _photoPending)
                  TextButton(
                    onPressed: () => setState(() {
                      _photoMode = 'keep';
                      _photoPending = false;
                      _photoBytes = null;
                      _photoUrl =
                          _context?['photoUrl'] as String? ??
                          widget.user.photoUrl;
                      _media.forget();
                      _error = null;
                    }),
                    child: const Text('Keep current photo'),
                  ),
                if (AppEnvironment.profilePhotosEnabled)
                  TextButton(
                    onPressed: () => setState(() {
                      _photoMode = 'remove';
                      _error = null;
                      _photoPending = false;
                      _photoBytes = null;
                      _photoUrl = null;
                      _media.forget();
                    }),
                    child: const Text('Use default avatar'),
                  ),
                const SizedBox(height: 28),

                _buildFieldLabel(tr(context, 'FULL NAME')),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.person_outlined,
                      size: 18,
                      color: AppPalette.of(context).outline,
                    ),
                    fillColor: AppPalette.of(context).surfaceContainerHigh,
                  ),
                ),
                const SizedBox(height: 20),

                _buildFieldLabel(tr(context, 'EMAIL ADDRESS')),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  readOnly: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.mail_outlined,
                      size: 18,
                      color: AppPalette.of(context).outline,
                    ),
                    fillColor: AppPalette.of(context).surfaceContainerHigh,
                  ),
                ),
                const SizedBox(height: 20),

                _buildFieldLabel(tr(context, 'LOCATION / BARANGAY')),
                const SizedBox(height: 8),
                TextField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: AppPalette.of(context).outline,
                    ),
                    fillColor: AppPalette.of(context).surfaceContainerHigh,
                  ),
                ),
                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: AppPalette.of(
                      context,
                    ).primaryActionDecoration(radius: 16),
                    child: ElevatedButton(
                      onPressed: _saveDetails,
                      style: ElevatedButton.styleFrom(
                        surfaceTintColor: Colors.transparent,
                        elevation: AppPalette.of(context).isDark ? 0 : null,
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              tr(context, 'Save Details'),
                              style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
          color: AppPalette.of(context).onSurfaceVariant,
        ),
      ),
    );
  }
}
