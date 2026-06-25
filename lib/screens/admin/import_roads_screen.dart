import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/app_state_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/constants.dart';

class CandidateRoad {
  final String name;
  final List<List<Map<String, double>>> geometrySegments;
  final bool isExisting;
  bool isSelected;

  CandidateRoad({
    required this.name,
    required this.geometrySegments,
    required this.isExisting,
    this.isSelected = false,
  });
}

class ImportRoadsScreen extends StatefulWidget {
  const ImportRoadsScreen({super.key});

  @override
  State<ImportRoadsScreen> createState() => _ImportRoadsScreenState();
}

class _ImportRoadsScreenState extends State<ImportRoadsScreen> {
  bool _isLoading = false;
  bool _isImporting = false;
  String _statusMessage = '';
  List<CandidateRoad> _candidateRoads = [];

  String _normalizeRoadName(String name) {
    String normalized = name.toLowerCase();
    // Collapse spaces between single letters (e.g. "m h del pilar" -> "mh del pilar")
    normalized = normalized.replaceAllMapped(RegExp(r'\b([a-z])\s+(?=[a-z]\b)'), (match) => match.group(1)!);
    
    return normalized
        .replaceAll('street', '')
        .replaceAll('st.', '')
        .replaceAll('st', '')
        .replaceAll('road', '')
        .replaceAll('rd', '')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _fetchCandidateRoads() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Querying OSM for roads within Marulas...';
      _candidateRoads = [];
    });

    try {
      final String query = '''
        [out:json];
        (
          way["highway"]["name"](poly:"${Constants.marulasPoly}");
        );
        out geom;
      ''';

      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: {
          'User-Agent': 'SafePathsApp/1.0 (contact: admin@marulas.gov.ph)',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'data': query},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;

        Map<String, List<List<Map<String, double>>>> groupedGeometries = {};

        for (var el in elements) {
          if (el['type'] == 'way' && el['tags'] != null && el['tags']['name'] != null && el['geometry'] != null) {
            String rawName = el['tags']['name'];
            // Normalize name
            String cleanName = rawName.trim();
            
            List<Map<String, double>> segment = [];
            for (var pt in el['geometry']) {
              if (pt['lat'] != null && pt['lon'] != null) {
                segment.add({
                  'lat': (pt['lat'] as num).toDouble(),
                  'lng': (pt['lon'] as num).toDouble(),
                });
              }
            }

            if (segment.isNotEmpty) {
              groupedGeometries.putIfAbsent(cleanName, () => []).add(segment);
            }
          }
        }

        final appState = AppStateService.instance;
        final existingNames = appState.roads.map((e) => _normalizeRoadName(e.name)).toSet();

        List<CandidateRoad> candidates = [];
        for (var entry in groupedGeometries.entries) {
          bool existing = existingNames.contains(_normalizeRoadName(entry.key));
          candidates.add(CandidateRoad(
            name: entry.key,
            geometrySegments: entry.value,
            isExisting: existing,
            isSelected: !existing, // Auto-select new roads
          ));
        }

        // Sort: new roads first, then alphabetical
        candidates.sort((a, b) {
          if (a.isExisting != b.isExisting) return a.isExisting ? 1 : -1;
          return a.name.compareTo(b.name);
        });

        setState(() {
          _candidateRoads = candidates;
          _statusMessage = 'Found ${candidates.length} candidate roads.';
        });
      } else {
        setState(() {
          _statusMessage = 'Failed to fetch roads (HTTP ${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error fetching roads: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _importSelectedRoads() async {
    final selected = _candidateRoads.where((r) => r.isSelected && !r.isExisting).toList();
    if (selected.isEmpty) return;

    setState(() {
      _isImporting = true;
      _statusMessage = 'Importing ${selected.length} roads to Firestore...';
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final collection = FirebaseFirestore.instance.collection('roads');

      for (var road in selected) {
        final docRef = collection.doc();
        
        // LineString format for geometry (flattened to avoid Firestore nested array limits)
        List<Map<String, double>> flattenedCoords = [];
        for (var segment in road.geometrySegments) {
          for (var pt in segment) {
            flattenedCoords.add({'lat': pt['lat']!, 'lng': pt['lng']!});
          }
        }

        final geometryMap = {
          'type': 'LineString',
          'coordinates': flattenedCoords,
        };

        batch.set(docRef, {
          'name': road.name,
          'status': 'passable',
          'notes': '',
          'vulnerability': 'medium', // Default to medium as requested
          'updatedAt': FieldValue.serverTimestamp(),
          'geometry': geometryMap,
          'neighbors': [],
          'riskScore': 0.0,
          'riskCategory': 'Safe',
          'source': 'osm',
          'isVerified': true,
          'importedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      setState(() {
        _statusMessage = 'Import successful. Rebuilding graph...';
      });

      // Rebuild graph
      final appState = AppStateService.instance;
      final stats = await appState.buildAndVerifyRoadGraph();
      
      // Create Audit Log
      await FirebaseFirestore.instance.collection('system_audits').add({
        'type': 'road_import',
        'importedAt': FieldValue.serverTimestamp(),
        'importedRoadsCount': selected.length,
        'ignoredRoadsCount': _candidateRoads.length - selected.length,
        'algorithmVersion': '1.0', // SafePaths Routing Graph Engine Version
        'riskConfigVersion': '1.0', // Predictive Risk Settings Version
        'graphStats': {
          'averageNeighbors': stats['avgNeighbors'] ?? 0.0,
          'disconnectedRoads': stats['disconnectedRoads'] ?? 0,
          'maximumNeighbors': stats['maximumNeighbors'] ?? 0,
          'totalRoads': stats['totalRoads'] ?? 0,
        }
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Import Successful', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: AppColors.onSurface)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${selected.length} roads imported.', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  const SizedBox(height: 16),
                  Text('Graph Statistics:', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Text('Average Neighbors: ${(stats['avgNeighbors'] ?? 0.0).toStringAsFixed(1)}', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
                  Text('Disconnected Roads: ${stats['disconnectedRoads'] ?? 0}', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  Text('System Ready.', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.secondary)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // close dialog
                    Navigator.pop(context); // close screen
                  },
                  child: Text('Done', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error during import: $e';
        _isImporting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Road import failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Import Roads',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: AppColors.onSurface,
          ),
        ),
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: AppColors.surfaceContainerLowest,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bulk Import from OpenStreetMap',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fetch and import road segments inside Barangay Marulas boundary. Existing roads are marked and disabled.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading || _isImporting ? null : _fetchCandidateRoads,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading && _candidateRoads.isEmpty
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Scan Marulas Roads',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                if (_statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _candidateRoads.isEmpty
                ? Center(
                    child: Text(
                      'No roads scanned yet.',
                      style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _candidateRoads.length,
                    itemBuilder: (context, index) {
                      final road = _candidateRoads[index];
                      return CheckboxListTile(
                        value: road.isSelected,
                        onChanged: road.isExisting || _isImporting
                            ? null
                            : (val) {
                                setState(() {
                                  road.isSelected = val ?? false;
                                });
                              },
                        title: Text(
                          road.name,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: road.isExisting ? AppColors.onSurfaceVariant : AppColors.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '${road.geometrySegments.length} segments • ${road.isExisting ? 'Already Imported' : 'New Road'}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: road.isExisting ? AppColors.primary : AppColors.onSurfaceVariant,
                            fontWeight: road.isExisting ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.primary,
                      );
                    },
                  ),
          ),
          if (_candidateRoads.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -4),
                    blurRadius: 10,
                  )
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isImporting || _candidateRoads.where((r) => r.isSelected && !r.isExisting).isEmpty
                        ? null
                        : _importSelectedRoads,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isImporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Import Selected Roads',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    if (_isImporting)
      Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Importing roads...',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
    );
  }
}
