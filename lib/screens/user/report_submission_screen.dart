import '../../widgets/report_photo_attachment_card.dart';
import '../../widgets/report_flood_level_selector.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/formatters.dart';
import 'package:flutter/material.dart';
import '../../config/app_environment.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../utils/report_image.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/report_submission_coordinator.dart';
import '../../services/report_photo_uploader.dart';
import '../../services/spark_proof_client.dart';
import '../../widgets/report_upload_progress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/image_watermark_util.dart';
import '../../utils/geo_utils.dart';
import 'location_picker_screen.dart';

class ReportSubmissionScreen extends StatefulWidget {
  final String? prefilledRoadId;
  const ReportSubmissionScreen({super.key, this.prefilledRoadId});

  @override
  State<ReportSubmissionScreen> createState() => _ReportSubmissionScreenState();
}

class _ReportSubmissionScreenState extends State<ReportSubmissionScreen> {
  int? _selectedFloodLevel; // Explicit observation: 0=Low, 1=Medium, 2=High.
  bool _isEmergency = false;
  String? _selectedRoadId;
  final _descriptionController = TextEditingController();
  bool _showSuccess = false;
  File? _selectedImage;
  final Set<String> _temporaryPhotos = {};
  final ImagePicker _picker = ImagePicker();
  final _submission = ReportSubmissionCoordinator();
  final _photoUploader = ReportPhotoUploader();
  bool get _isUploading => _submission.isBusy;
  bool _isProcessingImage = false;
  Map<String, dynamic>? _manualLocation;
  DateTime? _observedAt;
  bool _isLocating = true;
  int _locationGeneration = 0;
  String _locationStatusMessage = 'Detecting location...';

  @override
  void initState() {
    super.initState();
    _submission.addListener(_onSubmissionChanged);
    _selectedRoadId = widget.prefilledRoadId;
    if (!AppEnvironment.reportsEnabled) {
      _isLocating = false;
      return;
    }
    if (_selectedRoadId == null) {
      _detectLocation();
    } else {
      _isLocating = false;
      _locationStatusMessage = 'Road pre-selected from map.';
      _detectLocation();
    }
  }

  void _onSubmissionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _detectLocation() async {
    final generation = ++_locationGeneration;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted || generation != _locationGeneration) return;
      if (!serviceEnabled) {
        setState(() {
          _isLocating = false;
          _locationStatusMessage = 'Location services disabled.';
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (!mounted || generation != _locationGeneration) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!mounted || generation != _locationGeneration) return;
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && generation == _locationGeneration && _isLocating) {
            setState(() {
              _locationStatusMessage = 'Still locating GPS (Poor signal)...';
            });
          }
        });

        Position? position;
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
        } catch (e) {
          position = await Geolocator.getLastKnownPosition();
          if (position == null) rethrow;
          if (DateTime.now().difference(position.timestamp).inMinutes > 5) {
            throw Exception('GPS_STALE');
          }
        }
        if (!mounted || generation != _locationGeneration) return;
        _manualLocation = {
          'lat': position.latitude,
          'lng': position.longitude,
          'source': 'gps',
          'gpsCapturedAt': position.timestamp.toUtc().toIso8601String(),
          'gpsAccuracyMeters': position.accuracy,
        };
        _snapToNearestRoad(
          position.latitude,
          position.longitude,
          isAutoDetect: true,
        );
      } else {
        setState(() {
          _isLocating = false;
          _locationStatusMessage = 'Location permission denied.';
        });
      }
    } catch (e) {
      if (mounted && generation == _locationGeneration) {
        setState(() {
          _isLocating = false;
          _locationStatusMessage = 'GPS unavailable.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, 'GPS unavailable — please use the map pin'),
            ),
          ),
        );
      }
    }
  }

  void _snapToNearestRoad(double lat, double lng, {bool isAutoDetect = false}) {
    String? nearestRoadId;
    double minGlobalDistance = double.infinity;

    for (var road in AppStateService.instance.roads) {
      if (road.geometry == null) continue;
      final distance = GeoUtils.distanceToGeometryMeters(
        lat,
        lng,
        road.geometry,
      );
      if (distance < minGlobalDistance) {
        minGlobalDistance = distance;
        nearestRoadId = road.id;
      }
    }

    if (mounted) {
      setState(() {
        _isLocating = false;
        if (widget.prefilledRoadId != null && isAutoDetect) {
          _selectedRoadId = widget.prefilledRoadId;
          _locationStatusMessage = 'Road pre-selected from map.';
        } else if (minGlobalDistance <= 500 && nearestRoadId != null) {
          _selectedRoadId = nearestRoadId;
          _locationStatusMessage = isAutoDetect
              ? 'Detected on monitored network.'
              : 'Pinned to monitored road.';
        } else if (_isEmergency && nearestRoadId != null) {
          _selectedRoadId = nearestRoadId;
          _locationStatusMessage = 'SOS Location Pinned (Nearest Road Linked).';
        } else {
          _selectedRoadId = null;
          _locationStatusMessage =
              'Location is too far from any monitored road.';
        }
      });
    }
  }

  Future<void> _pickImage() async {
    if (_isProcessingImage || _isUploading) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'ATTACH EVIDENCE PHOTO'),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: AppPalette.of(context).primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, 'Choose Photo Source'),
                style: GoogleFonts.manrope(
                  fontSize: 20,
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
                    Icons.camera_alt,
                    color: AppPalette.of(context).primary,
                  ),
                ),
                title: Text(
                  tr(context, 'Take Photo (Camera)'),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AppPalette.of(context).onSurface,
                  ),
                ),
                subtitle: Text(
                  tr(context, 'Capture live incident evidence on-site'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppPalette.of(context).onSurfaceVariant,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _processImageCapture(ImageSource.camera);
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
                    Icons.photo_library,
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
                  tr(context, 'Select an existing photo from device storage'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppPalette.of(context).onSurfaceVariant,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _processImageCapture(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearTemporaryPhotos({String? keep}) async {
    final discard = _temporaryPhotos.where((path) => path != keep).toList();
    for (final path in discard) {
      _temporaryPhotos.remove(path);
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _processImageCapture(ImageSource source) async {
    if (_isProcessingImage || _isUploading) return;
    setState(() => _isProcessingImage = true);
    try {
      final XFile? picked = await _picker.pickImage(source: source);

      if (!mounted || picked == null) return;
      if (await picked.length() > maxReportPhotoBytes) {
        throw const FormatException(
          'Please choose an image smaller than 10 MB.',
        );
      }
      if (!mounted) return;

      setState(() {
        _isProcessingImage = true;
      });

      // Get road name or default locale
      String roadName = AppEnvironment.area.name;
      if (_selectedRoadId != null) {
        final road = AppStateService.instance.roads.firstWhere(
          (r) => r.id == _selectedRoadId,
          orElse: () => RoadStatus(
            id: '',
            name: AppEnvironment.area.name,
            status: 'passable',
            notes: '',
            updatedAt: DateTime.now(),
          ),
        );
        if (road.name.isNotEmpty) {
          roadName = '${road.name}, ${AppEnvironment.area.name}';
        }
      }

      // Coordinates: only stamp if real location is selected or acquired
      double? lat;
      double? lng;
      if (_manualLocation != null) {
        lat = (_manualLocation!['lat'] as num?)?.toDouble();
        lng = (_manualLocation!['lng'] as num?)?.toDouble();
      }

      // Determine authentic capture/modification time
      DateTime photoTimestamp;
      if (source == ImageSource.gallery) {
        try {
          photoTimestamp = File(picked.path).lastModifiedSync();
        } catch (_) {
          photoTimestamp = DateTime.now();
        }
      } else {
        photoTimestamp = DateTime.now();
      }

      // Validate the source encoding and decode off the UI thread before watermarking.
      final normalized = await compute(
        normalizeReportPhoto,
        await picked.readAsBytes(),
      );
      if (!mounted) return;
      final tempDir = await getTemporaryDirectory();
      final normalizedFile = File(
        '${tempDir.path}/report_input_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      _temporaryPhotos.add(normalizedFile.path);
      await normalizedFile.writeAsBytes(normalized);
      if (!mounted) return;

      // Apply watermark
      final watermarked = await ImageWatermarkUtil.applyWatermark(
        sourceFile: normalizedFile,
        locationName: roadName,
        lat: lat,
        lng: lng,
        timestamp: photoTimestamp,
        isLiveCamera: source == ImageSource.camera,
      );

      _temporaryPhotos.add(watermarked.path);
      if (mounted) {
        setState(() {
          _selectedImage = watermarked;
          _submission.invalidatePhoto();
          _photoUploader.forget();
          _isProcessingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Photo attached successfully.')),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error capturing/watermarking image: $e');
      if (mounted) {
        setState(() {
          _isProcessingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : tr(
                      context,
                      'Unable to process this photo. Please choose another JPG or PNG image.',
                    ),
            ),
          ),
        );
      }
    } finally {
      await _clearTemporaryPhotos(keep: mounted ? _selectedImage?.path : null);
      if (mounted) setState(() => _isProcessingImage = false);
    }
  }

  @override
  void dispose() {
    _submission.removeListener(_onSubmissionChanged);
    _submission.dispose();
    _photoUploader.dispose();
    unawaited(_clearTemporaryPhotos());
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppEnvironment.reportsEnabled) {
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, 'Reports'))),
        body: Center(
          child: Text(
            tr(
              context,
              'Photo reports are unavailable in SafePaths Test.\nUse the admin road-status screen to simulate a closure.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return PopScope(canPop: !_isUploading, child: _buildForm(context));
  }

  Widget _buildForm(BuildContext context) {
    final appState = AppStateService.instance;

    return Scaffold(
      appBar: AppTopBar(
        showBackButton: true,
        onBackPressed: () {
          if (!_isUploading) Navigator.of(context).pop();
        },
      ),
      backgroundColor: AppPalette.of(context).surface,
      body: SafeArea(
        bottom: true,
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _isUploading,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Text(
                      tr(context, 'NEW INCIDENT REPORT'),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: AppPalette.of(context).primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(
                        context,
                        _isEmergency
                            ? 'Urgent report'
                            : 'Report road conditions',
                      ),
                      style: GoogleFonts.manrope(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: AppPalette.of(context).onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        'Provide essential details. Your selected location will be included in this report.',
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Detected Location Banner
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _selectedRoadId != null
                            ? AppPalette.of(context).surfaceContainerLowest
                            : AppPalette.of(
                                context,
                              ).errorContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _selectedRoadId != null
                              ? AppPalette.of(
                                  context,
                                ).primary.withValues(alpha: 0.2)
                              : AppPalette.of(context).error,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _selectedRoadId != null
                                    ? Icons.check_circle
                                    : Icons.warning,
                                color: _selectedRoadId != null
                                    ? AppPalette.of(context).primary
                                    : AppPalette.of(context).error,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedRoadId != null
                                      ? tr(context, 'DETECTED LOCATION')
                                      : tr(context, 'LOCATION ERROR'),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: _selectedRoadId != null
                                        ? AppPalette.of(context).primary
                                        : AppPalette.of(context).error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isLocating)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: CircularProgressIndicator(),
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedRoadId != null
                                      ? appState.roads
                                            .firstWhere(
                                              (r) => r.id == _selectedRoadId,
                                              orElse: () => RoadStatus(
                                                id: '',
                                                name: 'Unknown Road',
                                                status: 'passable',
                                                notes: '',
                                                updatedAt: DateTime.now(),
                                              ),
                                            )
                                            .name
                                      : tr(context, 'Not on monitored network'),
                                  style: GoogleFonts.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppPalette.of(context).onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  tr(context, _locationStatusMessage),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppPalette.of(
                                      context,
                                    ).onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Flood level selection
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppPalette.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context, 'SELECT FLOOD LEVEL'),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(
                              context,
                              'Choose the level you observed. An administrator will review your report.',
                            ),
                          ),
                          const SizedBox(height: 16),
                          ReportFloodLevelSelector(
                            selected: _selectedFloodLevel,
                            onChanged: (value) =>
                                setState(() => _selectedFloodLevel = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // SOS Emergency Toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _isEmergency
                            ? AppPalette.of(
                                context,
                              ).error.withValues(alpha: 0.08)
                            : AppPalette.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isEmergency
                              ? AppPalette.of(context).error
                              : AppPalette.of(
                                  context,
                                ).outlineVariant.withValues(alpha: 0.15),
                          width: _isEmergency ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _isEmergency
                                  ? AppPalette.of(context).error
                                  : AppPalette.of(
                                      context,
                                    ).outlineVariant.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.emergency_rounded,
                              size: 18,
                              color: _isEmergency
                                  ? AppPalette.of(context).onError
                                  : AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(context, 'I need immediate rescue'),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _isEmergency
                                        ? AppPalette.of(context).error
                                        : AppPalette.of(context).onSurface,
                                  ),
                                ),
                                Text(
                                  tr(
                                    context,
                                    'Flag this report for urgent review.',
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppPalette.of(
                                      context,
                                    ).onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _isEmergency,
                            activeThumbColor: AppPalette.of(context).error,
                            onChanged: (val) {
                              setState(() {
                                _isEmergency = val;
                                if (_isEmergency) {
                                  if (_manualLocation != null &&
                                      _selectedRoadId == null) {
                                    _snapToNearestRoad(
                                      (_manualLocation!['lat'] as num)
                                          .toDouble(),
                                      (_manualLocation!['lng'] as num)
                                          .toDouble(),
                                    );
                                  }
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    ReportPhotoAttachmentCard(
                      preview: _selectedImage == null
                          ? null
                          : ResizeImage(
                              FileImage(_selectedImage!),
                              width: 1000,
                            ),
                      processing: _isProcessingImage,
                      onPick: _isUploading || _isProcessingImage
                          ? null
                          : _pickImage,
                      onRemove: _isUploading || _isProcessingImage
                          ? null
                          : () => setState(() {
                              _selectedImage = null;
                              _submission.invalidatePhoto();
                              _photoUploader.forget();
                            }),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isUploading || _isProcessingImage
                          ? null
                          : _chooseReportLocation,
                      icon: const Icon(Icons.my_location, size: 18),
                      label: Text(
                        tr(context, 'Review report location'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppPalette.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context, 'DESCRIPTION'),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descriptionController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: tr(
                                context,
                                "Describe the situation... (e.g. 'Road blocked by water, 2ft deep')",
                              ),
                              fillColor: AppPalette.of(
                                context,
                              ).surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppPalette.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(
                              context,
                              'When did you observe these conditions?',
                            ),
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).onSurface,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppPalette.of(context).surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.schedule_outlined,
                                  size: 20,
                                  color: AppPalette.of(context).primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _observedAt == null
                                        ? tr(
                                            context,
                                            'Observation time: now (recorded when you submit)',
                                          )
                                        : '${tr(context, 'Observation time')}: ${localizedDateTime(context, _observedAt!)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: AppPalette.of(
                                        context,
                                      ).onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isUploading
                                  ? null
                                  : _chooseObservationTime,
                              icon: const Icon(
                                Icons.edit_calendar_outlined,
                                size: 18,
                              ),
                              label: Text(
                                tr(context, 'Choose observation time'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _isUploading
                                  ? null
                                  : () => setState(() => _observedAt = null),
                              icon: const Icon(Icons.update_outlined, size: 18),
                              label: Text(tr(context, 'Observed now')),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ReportUploadProgress(
                      phase: _submission.phase,
                      progress: _submission.progress,
                    ),
                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _isUploading || _isProcessingImage
                            ? null
                            : _submitReport,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: AppPalette.of(context).tertiary,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppPalette.of(
                                  context,
                                ).tertiary.withValues(alpha: 0.2),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isUploading) ...[
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: AppPalette.of(context).onTertiary,
                                    strokeWidth: 2.5,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ] else ...[
                                Icon(
                                  Icons.send_rounded,
                                  color: AppPalette.of(context).onTertiary,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Flexible(
                                child: Text(
                                  _isUploading
                                      ? tr(context, 'PLEASE WAIT...')
                                      : tr(context, 'SUBMIT REPORT'),
                                  style: GoogleFonts.manrope(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppPalette.of(context).onTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            tr(context, 'TAP TO SEND EMERGENCY DATA'),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3.0,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(
                              context,
                              'Provided coordinates are checked against the road. GPS or a map pin does not independently verify what happened.',
                            ),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppPalette.of(
                                context,
                              ).onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Success overlay
            if (_showSuccess)
              Container(
                color: AppPalette.of(context).surface.withValues(alpha: 0.9),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppPalette.of(context).secondaryContainer,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          size: 48,
                          color: AppPalette.of(context).onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        tr(context, 'Report Received'),
                        style: GoogleFonts.manrope(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.of(context).onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 280,
                        child: Text(
                          tr(
                            context,
                            'Report saved for review. Stay clear of high water. Submission does not confirm that rescue has been dispatched.',
                          ),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: AppPalette.of(context).onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.of(context).primary,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            tr(context, 'Return to Map'),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseReportLocation() async {
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LocationPickerScreen()));
    if (mounted && result != null && result is Map<String, dynamic>) {
      _locationGeneration++;
      setState(() {
        _isLocating = false;
        _manualLocation = {...result, 'source': 'manual'};
        if (result.containsKey('roadId') && result['roadId'] != null) {
          _selectedRoadId = result['roadId'] as String;
          _locationStatusMessage = 'Pinned to monitored road.';
        } else {
          _selectedRoadId = null;
          _locationStatusMessage =
              'Location is too far from any monitored road.';
        }
      });
    }
  }

  Future<void> _chooseObservationTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _observedAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_observedAt ?? now),
      builder: twelveHourPickerBuilder,
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selected.isAfter(now.add(const Duration(minutes: 1))) ||
        now.difference(selected) >= const Duration(hours: 24)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'Choose an observation within the last 24 hours.'),
          ),
        ),
      );
      return;
    }
    setState(() => _observedAt = selected);
  }

  void _submitReport() async {
    if (!AppEnvironment.reportsEnabled || _isProcessingImage || _isUploading) {
      return;
    }
    final description = _descriptionController.text.trim();
    if (_selectedFloodLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'Please choose the flood level you observed.'),
          ),
        ),
      );
      return;
    }
    if (_selectedRoadId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Please select a road.'))),
      );
      return;
    }
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Please enter a description.'))),
      );
      return;
    }

    String floodLevelText = 'Medium';
    if (_selectedFloodLevel == 0) floodLevelText = 'Low';
    if (_selectedFloodLevel == 2) floodLevelText = 'High';

    final roadIndex = AppStateService.instance.roads.indexWhere(
      (r) => r.id == _selectedRoadId,
    );
    if (roadIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Selected road is no longer available. Please pick another.',
            ),
          ),
        ),
      );
      return;
    }
    final road = AppStateService.instance.roads[roadIndex];

    String titleText = 'Flooding: ${road.name}';
    if (_selectedFloodLevel == 0) titleText = 'Water Alert: ${road.name}';
    if (_selectedFloodLevel == 2) titleText = 'Deep Water: ${road.name}';

    if (_manualLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Failed to determine location. Please use the map pin.',
            ),
          ),
        ),
      );
      return;
    }

    final locationData = Map<String, dynamic>.from(_manualLocation!);
    // Retrying must not make old evidence appear newer.
    _observedAt ??= DateTime.now();
    locationData['observedAt'] = _observedAt!.toUtc().toIso8601String();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Please sign in again.'))),
      );
      return;
    }
    final image = _selectedImage;
    final selectedRoadId = road.id;
    final emergency = _isEmergency;
    final photoKey = image == null ? null : '$uid:${image.path}';
    try {
      await _submission.submit(
        photoKey: photoKey,
        prepare: () async =>
            compute(prepareReportImage, await image!.readAsBytes()),
        upload: (bytes, progress) =>
            _photoUploader.upload(photoKey!, uid, bytes, progress),
        save: (imageUrl) async {
          if (FirebaseAuth.instance.currentUser?.uid != uid) {
            throw StateError('ACCOUNT_CHANGED');
          }
          if (imageUrl != null) locationData['imageUrl'] = imageUrl;
          await AppStateService.instance.submitReport(
            emergency ? '[SOS RESCUE] $titleText' : titleText,
            description,
            floodLevelText,
            selectedRoadId,
            locationData,
            emergency,
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      if ((e is SparkProofException && e.code == 'resource-exhausted') ||
          e.toString().contains('SPAM_COOLDOWN')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Please wait 5 minutes before submitting another report to prevent spam.',
              ),
            ),
          ),
        );
      } else if (e.toString().contains('OUT_OF_RANGE')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'The provided location is too far from the selected road. Check your GPS or map pin.',
              ),
            ),
          ),
        );
      } else {
        final unavailablePhoto =
            (e is SparkProofException && e.code == 'photo-unavailable') ||
            e.toString().contains('Photo is unavailable');
        if (unavailablePhoto) {
          _submission.invalidatePhoto();
          _photoUploader.forget();
        }
        final message = unavailablePhoto
            ? 'Your attached photo is no longer available online. Retry to upload it again.'
            : e is SparkProofException
            ? e.message
            : e is PhotoUploadException
            ? e.message
            : e is FormatException
            ? 'This photo cannot be processed. Please choose another JPG or PNG image.'
            : _submission.hasUploadedPhoto
            ? 'We could not confirm your report was saved. Retry to finish; your uploaded photo will be reused.'
            : 'Report could not be saved. Check your connection and retry; your form is preserved.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    if (!mounted || _submission.phase != ReportSubmissionPhase.complete) return;
    setState(() => _showSuccess = true);
  }
}
