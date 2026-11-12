import '../data/marulas_landmarks.dart';
import '../utils/constants.dart';

class StudyArea {
  final String id, name, searchSuffix, polygon;
  final double latitude, longitude, south, west, north, east;
  final List<MarulasLandmark> landmarks;
  final List<Map<String, dynamic>> stagingFacilities;

  const StudyArea({
    required this.id,
    required this.name,
    required this.searchSuffix,
    required this.latitude,
    required this.longitude,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.polygon,
    this.landmarks = const [],
    this.stagingFacilities = const [],
  });

  String get bbox => '$west,$south,$east,$north';
  String get viewbox => '$west,$north,$east,$south';
  List<MarulasLandmark> searchLandmarks(String query) =>
      MarulasLandmarksCatalog.search(query, landmarks: landmarks);

  static const marulas = StudyArea(
    id: 'marulas',
    name: 'Barangay Marulas',
    searchSuffix: 'Marulas Valenzuela',
    latitude: 14.6761,
    longitude: 120.9842,
    south: 14.6660,
    west: 120.9680,
    north: 14.6855,
    east: 120.9995,
    polygon: Constants.marulasPoly,
    landmarks: MarulasLandmarksCatalog.all,
    // No beneficiary-approved staging sites or entrance pins yet. The halt
    // dialog supports an empty list; do not recommend unverified refuges.
  );

  static const fieldtest = StudyArea(
    id: 'nearby_test',
    name: 'Nearby Test Area',
    searchSuffix: '',
    latitude: 14.676139,
    longitude: 121.009417,
    south: 14.667156,
    west: 121.000131,
    north: 14.685122,
    east: 121.018703,
    polygon:
        '14.667156 121.000131 14.667156 121.018703 14.685122 121.018703 14.685122 121.000131',
  );
}
