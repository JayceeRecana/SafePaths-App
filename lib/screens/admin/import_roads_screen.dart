import '../../services/road_maintenance_service.dart';
import '../../services/spark_proof_client.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import '../../config/app_environment.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/app_state_service.dart';
import '../../services/test_road_import.dart';
import '../../utils/geo_utils.dart';
import '../../widgets/app_map.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;

class CandidateRoad {
  final String? sourceId;
  final String name;
  final List<List<Map<String, double>>> geometrySegments;
  final bool isExisting;
  bool isSelected;

  CandidateRoad({
    this.sourceId,
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
    normalized = normalized.replaceAllMapped(
      RegExp(r'\b([a-z])\s+(?=[a-z]\b)'),
      (match) => match.group(1)!,
    );

    // Strip common road designation suffixes with word-boundary regex to avoid mangling words like "East" or "Castle"
    normalized = normalized.replaceAll(
      RegExp(
        r'\b(?:street|st|road|rd|avenue|ave|drive|dr|boulevard|blvd|highway|hwy)\b\.?',
        caseSensitive: false,
      ),
      '',
    );

    return normalized
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _fetchCandidateRoads() async {
    setState(() {
      _isLoading = true;
      _statusMessage =
          'Querying OSM for roads within the selected study area...';
      _candidateRoads = [];
    });

    try {
      final String query =
          (AppEnvironment.isFieldTest || AppEnvironment.mainBackendRequested)
          ? TestRoadImport.query(AppEnvironment.area)
          : '''
        [out:json][timeout:25];
        (
          way["highway"]["name"](poly:"${AppEnvironment.area.polygon}");
        );
        out geom;
      ''';

      final endpoints = [
        'https://overpass.openstreetmap.fr/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://lz4.overpass-api.de/api/interpreter',
        'https://overpass-api.de/api/interpreter',
      ];

      http.Response? response;
      for (final ep in endpoints) {
        try {
          final res = await http
              .post(
                Uri.parse(ep),
                headers: {
                  'User-Agent':
                      'SafePathsApp/1.0 (contact: admin@marulas.gov.ph)',
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: {'data': query},
              )
              .timeout(const Duration(seconds: 15));

          if (res.statusCode == 200) {
            response = res;
            break;
          }
        } catch (_) {
          continue;
        }
      }

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;

        if (AppEnvironment.isFieldTest || AppEnvironment.mainBackendRequested) {
          final existing = AppStateService.instance.roads
              .map((r) => r.id)
              .toSet();
          final existingSegments = AppEnvironment.mainBackendRequested
              ? AppStateService.instance.roads
                    .expand(
                      (road) => GeoUtils.extractSegments(road.geometry).map(
                        (line) => TestRoadImport.segmentKey(
                          line
                              .map(
                                (p) => <String, double>{
                                  'lng': p.lng,
                                  'lat': p.lat,
                                },
                              )
                              .toList(),
                        ),
                      ),
                    )
                    .toSet()
              : <String>{};
          final candidates =
              TestRoadImport.parse(elements)
                  .map(
                    (r) => CandidateRoad(
                      sourceId: r.id,
                      name: r.name,
                      geometrySegments: [r.points],
                      isExisting:
                          existing.contains(r.id) ||
                          existingSegments.contains(
                            TestRoadImport.segmentKey(r.points),
                          ),
                      isSelected:
                          !existing.contains(r.id) &&
                          !existingSegments.contains(
                            TestRoadImport.segmentKey(r.points),
                          ),
                    ),
                  )
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
          if (mounted)
            setState(() {
              _candidateRoads = candidates;
              _statusMessage =
                  'Found ${candidates.length} road segments. Preview and select before importing.';
            });
          return;
        }

        Map<String, List<List<Map<String, double>>>> groupedGeometries = {};

        for (var el in elements) {
          if (el['type'] == 'way' &&
              el['tags'] != null &&
              el['tags']['name'] != null &&
              el['geometry'] != null) {
            String rawName = el['tags']['name'];
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
              if (!AppEnvironment.isFieldTest &&
                  cleanName.toLowerCase().contains('macarthur')) {
                // Segment into 3 distinct CCTV flood zones by latitude:
                // 1. Fatima / OLFU (North): lat >= 14.6780
                // 2. Marulas Market (Center): 14.6755 <= lat < 14.6780
                // 3. BBB (South): lat < 14.6755
                List<Map<String, double>> fatimaPts = [];
                List<Map<String, double>> marketPts = [];
                List<Map<String, double>> bbbPts = [];

                for (var pt in segment) {
                  final lat = pt['lat']!;
                  if (lat >= 14.6780) {
                    fatimaPts.add(pt);
                  } else if (lat >= 14.6755) {
                    marketPts.add(pt);
                  } else {
                    bbbPts.add(pt);
                  }
                }

                if (fatimaPts.isNotEmpty) {
                  groupedGeometries
                      .putIfAbsent(
                        'MacArthur Highway (Fatima / OLFU)',
                        () => [],
                      )
                      .add(fatimaPts);
                }
                if (marketPts.isNotEmpty) {
                  groupedGeometries
                      .putIfAbsent(
                        'MacArthur Highway (Marulas Public Market)',
                        () => [],
                      )
                      .add(marketPts);
                }
                if (bbbPts.isNotEmpty) {
                  groupedGeometries
                      .putIfAbsent('MacArthur Highway (BBB)', () => [])
                      .add(bbbPts);
                }
              } else {
                groupedGeometries.putIfAbsent(cleanName, () => []).add(segment);
              }
            }
          }
        }

        final appState = AppStateService.instance;
        final existingNames = appState.roads
            .map((e) => _normalizeRoadName(e.name))
            .toSet();

        List<CandidateRoad> candidates = [];
        for (var entry in groupedGeometries.entries) {
          bool existing = existingNames.contains(_normalizeRoadName(entry.key));
          candidates.add(
            CandidateRoad(
              name: entry.key,
              geometrySegments: entry.value,
              isExisting: existing,
              isSelected: !existing, // Auto-select new roads
            ),
          );
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
          _statusMessage =
              'Failed to fetch roads (${response?.statusCode != null ? "HTTP " + response!.statusCode.toString() : "Mirrors Busy/Timeout"})';
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
    final selected = _candidateRoads
        .where((r) => r.isSelected && !r.isExisting)
        .toList();
    if (selected.isEmpty) return;

    setState(() {
      _isImporting = true;
      _statusMessage = 'Importing ${selected.length} roads to Firestore...';
    });

    try {
      var importedCount = selected.length, skippedCount = 0;
      Map<String, dynamic> stats;
      if (AppEnvironment.sparkCoreEnabled) {
        final result = await RoadMaintenanceService.importRoads(
          selected
              .map(
                (road) => <String, dynamic>{
                  'id': road.sourceId,
                  'name': road.name,
                  'geometry': {
                    'type': 'MultiLineString',
                    'segments': road.geometrySegments
                        .map(
                          (segment) => {
                            'points': segment
                                .map(
                                  (p) => {'lat': p['lat']!, 'lng': p['lng']!},
                                )
                                .toList(),
                          },
                        )
                        .toList(),
                  },
                },
              )
              .toList(),
        );
        importedCount = result['createdCount'] as int;
        skippedCount = result['skippedCount'] as int;
        stats = Map<String, dynamic>.from(result['graphStats'] as Map);
      } else {
        var batch = FirebaseFirestore.instance.batch();
        var batchCount = 0;
        final collection = FirebaseFirestore.instance.collection('roads');

        for (var road in selected) {
          // Use sanitized road name as doc ID so it is human-readable in Firestore
          // and re-importing the same road always overwrites instead of duplicating.
          final docId =
              road.sourceId ??
              road.name
                  .toLowerCase()
                  .trim()
                  .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                  .replaceAll(
                    RegExp(r'^_+|_+$'),
                    '',
                  ); // strip leading/trailing underscores
          final docRef = collection.doc(docId);

          // Store each OSM way as its own segment (MultiLineString).
          // NEVER flatten all segments into one LineString — that connects the
          // END of one way to the START of the next, creating diagonal zig-zag
          // artifacts across city blocks when they are not spatially adjacent.
          final firestoreSafeSegments = road.geometrySegments.map((seg) {
            return {
              'points': seg
                  .map((pt) => {'lat': pt['lat']!, 'lng': pt['lng']!})
                  .toList(),
            };
          }).toList();

          final geometryMap = {
            'type': 'MultiLineString',
            'segments': firestoreSafeSegments,
          };

          batch.set(docRef, {
            if (AppEnvironment.sparkCoreEnabled)
              'studyArea': AppEnvironment.area.id,
            if (AppEnvironment.sparkCoreEnabled)
              'riskInputsUpdatedAt': FieldValue.serverTimestamp(),
            'name': road.name,
            'status': 'passable',
            'notes': '',
            'vulnerability': 'medium',
            'updatedAt': FieldValue.serverTimestamp(),
            'geometry': geometryMap,
            'neighbors': [],
            'riskScore': 0.0,
            'riskCategory': 'Safe',
            'source': 'osm',
            'isVerified': false,
            'importedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          if (AppEnvironment.sparkCoreEnabled)
            batch.set(FirebaseFirestore.instance.doc('system/road_inputs'), {
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          if (++batchCount == 200) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            batchCount = 0;
          }
        }

        if (batchCount > 0) await batch.commit();

        setState(() {
          _statusMessage = 'Import successful. Rebuilding graph...';
        });

        // Rebuild graph
        final appState = AppStateService.instance;
        stats = await appState.buildAndVerifyRoadGraph();

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
          },
        });
      }

      if (mounted) {
        setState(() => _isImporting = false);
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: AppPalette.of(context).surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                tr(context, 'Import Successful'),
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  color: AppPalette.of(context).onSurface,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$importedCount roads imported. $skippedCount existing roads preserved.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppPalette.of(context).onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr(context, 'Graph Statistics:'),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: AppPalette.of(context).primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Average Neighbors: ${(stats['avgNeighbors'] ?? 0.0).toStringAsFixed(1)}',
                    style: GoogleFonts.inter(
                      color: AppPalette.of(context).onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Disconnected Roads: ${stats['disconnectedRoads'] ?? 0}',
                    style: GoogleFonts.inter(
                      color: AppPalette.of(context).onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr(
                      context,
                      'Import saved. Review road conditions before use.',
                    ),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppPalette.of(context).secondary,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // close dialog
                    Navigator.pop(context); // close screen
                  },
                  child: Text(
                    tr(context, 'Done'),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: AppPalette.of(context).primary,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _statusMessage = e is SparkProofException
              ? e.message
              : 'Import was not confirmed. Preserve the selection and retry.';
          _isImporting = false;
        });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Road import failed. Please try again.')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isImporting,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppPalette.of(context).surface,
            appBar: AppBar(
              title: Text(
                tr(context, 'Import Roads'),
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: AppPalette.of(context).onSurface,
                ),
              ),
              backgroundColor: AppPalette.of(context).surfaceContainerLowest,
              elevation: 0,
              iconTheme: IconThemeData(color: AppPalette.of(context).onSurface),
            ),
            body: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  color: AppPalette.of(context).surfaceContainerLowest,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'Bulk Import from OpenStreetMap'),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppPalette.of(context).onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          context,
                          'Fetch and import road segments inside the selected study area boundary. Existing roads are marked and disabled.',
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppPalette.of(context).onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading || _isImporting
                              ? null
                              : _fetchCandidateRoads,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.of(context).primary,
                            foregroundColor: AppPalette.of(context).onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading && _candidateRoads.isEmpty
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.of(context).onPrimary,
                                  ),
                                )
                              : Text(
                                  tr(context, 'Scan Area Roads'),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                  ),
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
                            color: AppPalette.of(context).primary,
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
                            tr(context, 'No roads scanned yet.'),
                            style: GoogleFonts.inter(
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _candidateRoads.length,
                          itemBuilder: (context, index) {
                            final road = _candidateRoads[index];
                            return CheckboxListTile(
                              secondary: AppEnvironment.isFieldTest
                                  ? IconButton(
                                      icon: const Icon(Icons.map_outlined),
                                      tooltip: tr(
                                        context,
                                        'Preview road segment',
                                      ),
                                      onPressed: () => showDialog(
                                        context: context,
                                        builder: (context) => Dialog(
                                          child: SizedBox(
                                            height: 500,
                                            width: 600,
                                            child: Column(
                                              children: [
                                                ListTile(
                                                  title: Text(road.name),
                                                  trailing: IconButton(
                                                    icon: const Icon(
                                                      Icons.close,
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: AppMap(
                                                    routePoints: road
                                                        .geometrySegments
                                                        .first
                                                        .map(
                                                          (p) => Position(
                                                            p['lng']!,
                                                            p['lat']!,
                                                          ),
                                                        )
                                                        .toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
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
                                  color: road.isExisting
                                      ? AppPalette.of(context).onSurfaceVariant
                                      : AppPalette.of(context).onSurface,
                                ),
                              ),
                              subtitle: Text(
                                '${road.geometrySegments.length} segments • ${road.isExisting ? 'Already Imported' : 'New Road'}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: road.isExisting
                                      ? AppPalette.of(context).primary
                                      : AppPalette.of(context).onSurfaceVariant,
                                  fontWeight: road.isExisting
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: AppPalette.of(context).primary,
                            );
                          },
                        ),
                ),
                if (_candidateRoads.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).surfaceContainerLowest,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          offset: const Offset(0, -4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              _isImporting ||
                                  _candidateRoads
                                      .where(
                                        (r) => r.isSelected && !r.isExisting,
                                      )
                                      .isEmpty
                              ? null
                              : _importSelectedRoads,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.of(context).primary,
                            foregroundColor: AppPalette.of(context).onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isImporting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.of(context).onPrimary,
                                  ),
                                )
                              : Text(
                                  tr(context, 'Import Selected Roads'),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
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
                    CircularProgressIndicator(
                      color: AppPalette.of(context).primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'Importing roads...'),
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
      ),
    );
  }
}
