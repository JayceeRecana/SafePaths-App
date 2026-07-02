import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'location_picker_screen.dart';

class ReportSubmissionScreen extends StatefulWidget {
  final String? prefilledRoadId;
  const ReportSubmissionScreen({super.key, this.prefilledRoadId});

  @override
  State<ReportSubmissionScreen> createState() => _ReportSubmissionScreenState();
}

class _ReportSubmissionScreenState extends State<ReportSubmissionScreen> {
  int _selectedFloodLevel = 2; // 0=Low, 1=Medium, 2=High
  String? _selectedRoadId;
  final _descriptionController = TextEditingController();
  bool _showSuccess = false;
  File? _selectedImage;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();
  Map<String, dynamic>? _manualLocation;
  bool _isLocating = true;
  String _locationStatusMessage = 'Detecting location...';

  @override
  void initState() {
    super.initState();
    _selectedRoadId = widget.prefilledRoadId;
    if (_selectedRoadId == null) {
      _detectLocation();
    } else {
      _isLocating = false;
      _locationStatusMessage = 'Road pre-selected from map.';
      _detectLocation();
    }
  }

  Future<void> _detectLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLocating = false;
          _locationStatusMessage = 'Location services disabled.';
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _isLocating) {
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
          if (position.timestamp != null && DateTime.now().difference(position.timestamp!).inMinutes > 5) {
            throw Exception('GPS_STALE');
          }
        }
        _manualLocation = {'lat': position.latitude, 'lng': position.longitude};
        _snapToNearestRoad(position.latitude, position.longitude, isAutoDetect: true);
      } else {
        setState(() {
          _isLocating = false;
          _locationStatusMessage = 'Location permission denied.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationStatusMessage = 'GPS unavailable.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS unavailable — please use the map pin')),
        );
      }
    }
  }

  void _snapToNearestRoad(double lat, double lng, {bool isAutoDetect = false}) {
    String? nearestRoadId;
    double minGlobalDistance = double.infinity;
    
    for (var road in AppStateService.instance.roads) {
      if (road.geometry != null && road.geometry!['coordinates'] != null) {
        final coords = road.geometry!['coordinates'] as List<dynamic>;
        for (var coord in coords) {
          double? rLng, rLat;
          if (coord is Map) {
            rLng = (coord['lon'] as num?)?.toDouble();
            rLat = (coord['lat'] as num?)?.toDouble();
          } else if (coord is List && coord.length >= 2) {
            rLng = (coord[0] as num?)?.toDouble();
            rLat = (coord[1] as num?)?.toDouble();
          }
          if (rLng == null || rLat == null) continue;
            
          double dist = Geolocator.distanceBetween(lat, lng, rLat, rLng);
          if (dist < minGlobalDistance) {
            minGlobalDistance = dist;
            nearestRoadId = road.id;
          }
        }
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
          _locationStatusMessage = isAutoDetect ? 'Detected on monitored network.' : 'Pinned to monitored road.';
        } else {
          _selectedRoadId = null;
          _locationStatusMessage = 'Location is too far from any monitored road.';
        }
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      XFile? image;
      try {
        image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
      } catch (e) {
        try {
          image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
        } catch (e2) {
          debugPrint('Image pick failed: $e2');
        }
      }
      if (image != null) {
        setState(() {
          _selectedImage = File(image!.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }



  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateService.instance;

    return Scaffold(
      appBar: AppTopBar(
        showBackButton: true,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: true,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    'NEW INCIDENT REPORT',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Emergency Submission',
                    style: GoogleFonts.manrope(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Provide essential details quickly. Your location is being monitored.',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Detected Location Banner
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _selectedRoadId != null 
                        ? AppColors.surfaceContainerLowest 
                        : AppColors.errorContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _selectedRoadId != null 
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.error,
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
                              _selectedRoadId != null ? Icons.check_circle : Icons.warning,
                              color: _selectedRoadId != null ? AppColors.primary : AppColors.error,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedRoadId != null ? 'DETECTED LOCATION' : 'LOCATION ERROR',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: _selectedRoadId != null ? AppColors.primary : AppColors.error,
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
                                  ? appState.roads.firstWhere((r) => r.id == _selectedRoadId, orElse: () => RoadStatus(id: '', name: 'Unknown Road', status: 'passable', notes: '', updatedAt: DateTime.now())).name
                                  : 'Not on monitored network',
                                style: GoogleFonts.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _locationStatusMessage,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.onSurfaceVariant,
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
                      color: AppColors.surfaceContainerLowest,
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
                          'SELECT FLOOD LEVEL',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _FloodLevelButton(
                              icon: Icons.water_drop,
                              label: 'Low',
                              isSelected: _selectedFloodLevel == 0,
                              color: AppColors.secondary,
                              onTap: () =>
                                  setState(() => _selectedFloodLevel = 0),
                            ),
                            const SizedBox(width: 12),
                            _FloodLevelButton(
                              icon: Icons.flood,
                              label: 'Medium',
                              isSelected: _selectedFloodLevel == 1,
                              color: AppColors.primary,
                              onTap: () =>
                                  setState(() => _selectedFloodLevel = 1),
                            ),
                            const SizedBox(width: 12),
                            _FloodLevelButton(
                              icon: Icons.warning_rounded,
                              label: 'High',
                              isSelected: _selectedFloodLevel == 2,
                              color: AppColors.tertiary,
                              onTap: () =>
                                  setState(() => _selectedFloodLevel = 2),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Evidence and Location row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Evidence card
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: _selectedImage != null ? AppColors.secondaryContainer : AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(_selectedImage != null ? Icons.check_circle : Icons.add_a_photo, size: 20, color: _selectedImage != null ? AppColors.onSecondaryContainer : AppColors.primary),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(_selectedImage != null ? 'Photo Attached' : 'Add Photo', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _selectedImage != null ? AppColors.onSecondaryContainer : AppColors.onSurface), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Location card
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
                            );
                            if (result != null && result is Map<String, dynamic>) {
                              setState(() {
                                _manualLocation = result;
                                if (result.containsKey('roadId') && result['roadId'] != null) {
                                  _selectedRoadId = result['roadId'] as String;
                                  _locationStatusMessage = 'Pinned to monitored road.';
                                } else {
                                  _selectedRoadId = null;
                                  _locationStatusMessage = 'Location is too far from any monitored road.';
                                }
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.my_location, size: 20, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _manualLocation != null ? 'Pin Set' : 'Location', 
                                    style: GoogleFonts.inter(
                                      fontSize: 13, 
                                      fontWeight: FontWeight.w600, 
                                      color: _manualLocation != null ? AppColors.primary : AppColors.onSurface,
                                    ), 
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
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
                          'DESCRIPTION',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _descriptionController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText:
                                "Describe the situation... (e.g. 'Road blocked by water, 2ft deep')",
                            fillColor: AppColors.surfaceContainerLow,
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

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _submitReport,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: AppColors.tertiary,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.tertiary.withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isUploading) ...[
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              ),
                              const SizedBox(width: 12),
                            ] else ...[
                              const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                              const SizedBox(width: 12),
                            ],
                            Text(
                              _isUploading ? 'UPLOADING...' : 'SUBMIT REPORT',
                              style: GoogleFonts.manrope(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
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
                          'TAP TO SEND EMERGENCY DATA',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3.0,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your location is securely attached to verify accuracy.',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Success overlay
            if (_showSuccess)
              Container(
                color: AppColors.surface.withValues(alpha: 0.9),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.secondaryContainer,
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          size: 48,
                          color: AppColors.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Report Received',
                        style: GoogleFonts.manrope(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 280,
                        child: Text(
                          'Our team has been notified. Stay clear of high water areas and follow safe paths.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: AppColors.onSurfaceVariant,
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
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            'Return to Map',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
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

  void _submitReport() async {
    final description = _descriptionController.text.trim();
    if (_selectedRoadId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a road.')),
      );
      return;
    }
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description.')),
      );
      return;
    }
    
    if (_isUploading) return;
    
    setState(() {
      _isUploading = true;
    });

    String floodLevelText = 'Medium';
    if (_selectedFloodLevel == 0) floodLevelText = 'Low';
    if (_selectedFloodLevel == 2) floodLevelText = 'High';

    final roadIndex = AppStateService.instance.roads.indexWhere((r) => r.id == _selectedRoadId);
    if (roadIndex == -1) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected road is no longer available. Please pick another.')),
      );
      return;
    }
    final road = AppStateService.instance.roads[roadIndex];

    String titleText = 'Flooding: ${road.name}';
    if (_selectedFloodLevel == 0) titleText = 'Water Alert: ${road.name}';
    if (_selectedFloodLevel == 2) titleText = 'Deep Water: ${road.name}';

    if (_manualLocation == null) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to determine location. Please use the map pin.')),
      );
      return;
    }
    
    Map<String, dynamic> locationData = _manualLocation!;

    String? imageUrl;
    if (_selectedImage != null) {
      try {
        final ref = FirebaseStorage.instance.ref().child('reports/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_selectedImage!, SettableMetadata(contentType: 'image/jpeg'));
        imageUrl = await ref.getDownloadURL();
      } catch (e) {
        debugPrint('Image upload failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo failed to upload. Report submitted without attachment.')),
          );
        }
      }
    }
    
    if (imageUrl != null) {
      locationData['imageUrl'] = imageUrl;
    }

    try {
      await AppStateService.instance.submitReport(
        titleText,
        description,
        floodLevelText,
        _selectedRoadId,
        locationData,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });
      if (e.toString().contains('SPAM_COOLDOWN')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please wait 5 minutes before submitting another report to prevent spam.')));
      } else if (e.toString().contains('OUT_OF_RANGE')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your GPS location is too far from this road to verify accuracy. Report rejected.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submission failed.')));
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _showSuccess = true;
    });
  }
}

class _FloodLevelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _FloodLevelButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? (color == AppColors.tertiary
                    ? AppColors.tertiaryFixed
                    : AppColors.surfaceContainerLow)
                : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
