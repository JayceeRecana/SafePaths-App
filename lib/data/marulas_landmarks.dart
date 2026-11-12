import 'package:flutter/material.dart';
import '../utils/place_search.dart';

enum QuickDestinationCategory {
  hospitals,
  evacuationCenters,
  barangayHall,
  emergencyServices,
}

class MarulasLandmark {
  final String id;
  final String name;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final List<String> tags;
  final IconData icon;
  final Set<QuickDestinationCategory> quickCategories;

  /// False while this record's identity/location is unresolved. Keep the
  /// original coordinates for audit, but do not suggest them for routing.
  final bool routingAvailable;

  const MarulasLandmark({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    required this.tags,
    this.icon = Icons.place,
    this.quickCategories = const {},
    this.routingAvailable = true,
  });

  Map<String, dynamic> toFeatureMap() {
    return {
      'id': id,
      'text': name,
      'place_name': '$name, $address',
      'category': category,
      'center': [lng, lat],
      'icon': icon,
    };
  }
}

class MarulasLandmarksCatalog {
  /// Membership is explicit; descriptive tags never certify a service.
  /// Callers provide the active area's catalog and scope predicate.
  static List<MarulasLandmark> quickDestinations(
    QuickDestinationCategory category,
    Iterable<MarulasLandmark> landmarks, {
    required bool Function(double lat, double lng) isInScope,
  }) {
    final byId = <String, MarulasLandmark>{};
    for (final place in landmarks) {
      if (!place.routingAvailable ||
          !place.quickCategories.contains(category) ||
          !place.lat.isFinite ||
          !place.lng.isFinite ||
          place.lat.abs() > 90 ||
          place.lng.abs() > 180 ||
          !isInScope(place.lat, place.lng))
        continue;
      byId.putIfAbsent(place.id, () => place);
    }
    return byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  static const List<MarulasLandmark> all = [
    // --- Hospitals & Healthcare ---
    MarulasLandmark(
      id: 'fumc',
      quickCategories: {QuickDestinationCategory.hospitals},
      name: 'Fatima University Medical Center (FUMC)',
      category: 'Hospital / Healthcare',
      address: '120 MacArthur Highway, Marulas, Valenzuela',
      // Operator confirms branch/address. Public mapped POI corroborated by
      // OSM way 175024244; not a verified entrance. Pin review remains required.
      lat: 14.6780548,
      lng: 120.9802868,
      icon: Icons.local_hospital,
      tags: [
        'hospital',
        'clinic',
        'fumc',
        'fatima',
        'doctor',
        'medical',
        'emergency',
        'health',
        'macarthur',
      ],
    ),
    MarulasLandmark(
      id: 'marulas_health_center',
      routingAvailable: false, // Local identity and entrance need confirmation.
      name: 'Marulas Central Health Center',
      category: 'Hospital / Healthcare',
      address: 'P. Sevilla St, Marulas, Valenzuela',
      lat: 14.6758,
      lng: 120.9835,
      icon: Icons.medical_services,
      tags: [
        'hospital',
        'health',
        'center',
        'clinic',
        'sevilla',
        'doctor',
        'medical',
        'vaccine',
        'marulas health center',
      ],
    ),
    MarulasLandmark(
      id: 'red_cross_valenzuela',
      routingAvailable: false, // Operator address contradicts stored pin.
      quickCategories: {QuickDestinationCategory.emergencyServices},
      name: 'Philippine Red Cross - Valenzuela Chapter',
      category: 'Red Cross / Blood Station',
      address: 'Dahlia Street, Villa Teresa Subdivision, Marulas, Valenzuela',
      lat: 14.6778,
      lng: 120.9788,
      icon: Icons.health_and_safety,
      tags: [
        'red cross',
        'blood',
        'rescue',
        'emergency',
        'dahlia',
        'aid',
        'first aid',
        'medical',
        'clinic',
      ],
    ),
    MarulasLandmark(
      id: 'mercury_fatima',
      name: 'Mercury Drug - Fatima MacArthur',
      category: 'Pharmacy / Healthcare',
      address: 'MacArthur Highway cor. Fatima Ave, Marulas, Valenzuela',
      lat: 14.6781,
      lng: 120.9788,
      icon: Icons.medication,
      tags: ['mercury', 'drug', 'pharmacy', 'medicine', 'fatima', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'watsons_marulas',
      name: 'Watsons Pharmacy - Marulas MacArthur',
      category: 'Pharmacy / Healthcare',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6780,
      lng: 120.9791,
      icon: Icons.medication,
      tags: ['watsons', 'pharmacy', 'medicine', 'personal care', 'macarthur'],
    ),

    // --- Schools & Universities ---
    MarulasLandmark(
      id: 'olfu_main',
      name: 'Our Lady of Fatima University (OLFU Main)',
      category: 'School / University',
      address: '120 MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6788,
      lng: 120.9783,
      icon: Icons.school,
      tags: [
        'olfu',
        'fatima',
        'university',
        'college',
        'school',
        'campus',
        'macarthur',
        'rise tower',
      ],
    ),
    MarulasLandmark(
      id: 'marulas_elem_school',
      routingAvailable:
          false, // School identity/pin unresolved; no designation.
      name: 'Marulas Elementary School',
      category: 'School / Education',
      address: 'Serrano St, Marulas, Valenzuela',
      lat: 14.6750,
      lng: 120.9822,
      icon: Icons.emergency,
      tags: ['school', 'elementary', 'serrano'],
    ),
    MarulasLandmark(
      id: 'san_lorenzo_school',
      routingAvailable: false, // No verified local pin or evacuation approval.
      name: 'San Lorenzo Ruiz Parochial School',
      category: 'School / Church',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6770,
      lng: 120.9840,
      icon: Icons.school,
      tags: ['san lorenzo', 'ruiz', 'school', 'parochial', 'pio valenzuela'],
    ),
    MarulasLandmark(
      id: 'marulas_central_school',
      routingAvailable:
          false, // Legacy pin conflicts with current mapped search; resolve live.
      name: 'Marulas Central School',
      category: 'School / Education',
      address: 'P. Sevilla St, Marulas, Valenzuela',
      lat: 14.6752,
      lng: 120.9825,
      icon: Icons.school,
      tags: ['central', 'school', 'elementary', 'sevilla', 'education'],
    ),
    MarulasLandmark(
      id: 'valenzuela_sped_center',
      name: 'Valenzuela Special Education Center (SPED)',
      category: 'School / Education',
      address: 'Serrano St, Marulas, Valenzuela',
      lat: 14.6748,
      lng: 120.9820,
      icon: Icons.school,
      tags: ['sped', 'special education', 'school', 'serrano'],
    ),
    MarulasLandmark(
      id: 'st_bernadette_academy',
      name: 'St. Bernadette Academy of Valenzuela',
      category: 'School / Education',
      address: 'P. Gomez St, Marulas, Valenzuela',
      lat: 14.6760,
      lng: 120.9852,
      icon: Icons.school,
      tags: ['bernadette', 'academy', 'school', 'gomez', 'private school'],
    ),
    MarulasLandmark(
      id: 'children_of_mary',
      name: 'Children of Mary Immaculate College',
      category: 'School / University',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6785,
      lng: 120.9795,
      icon: Icons.school,
      tags: ['children of mary', 'cmic', 'college', 'school', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'constantino_elem_school',
      routingAvailable:
          false, // Legacy pin conflicts with current mapped search; resolve live.
      name: 'Constantino Elementary School',
      category: 'School / Education',
      address: 'Constantino Village, Marulas, Valenzuela',
      lat: 14.6720,
      lng: 120.9805,
      icon: Icons.school,
      tags: ['constantino', 'school', 'elementary', 'subdivision', 'village'],
    ),

    // --- Barangay, Government & Emergency Services ---
    MarulasLandmark(
      id: 'marulas_brgy_hall',
      routingAvailable: false, // Conflicting mapped hall locations.
      quickCategories: {QuickDestinationCategory.barangayHall},
      name: 'Marulas Barangay Hall & Multi-Purpose Complex',
      category: 'Government / Community',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6765,
      lng: 120.9845,
      icon: Icons.account_balance,
      tags: [
        'barangay',
        'hall',
        'brgy',
        'pio valenzuela',
        'government',
        'community',
        'services',
      ],
    ),
    MarulasLandmark(
      id: 'marulas_3s_center',
      routingAvailable:
          false, // Mapped site differs; entrance/services unresolved.
      quickCategories: {QuickDestinationCategory.emergencyServices},
      name: '3S Center Marulas (Sentro ng Sama-samang Serbisyo)',
      category: 'Government / Emergency',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6763,
      lng: 120.9842,
      icon: Icons.shield,
      tags: [
        '3s',
        'center',
        'serbisyo',
        'rescue',
        'emergency',
        'city hall',
        'pio valenzuela',
      ],
    ),
    MarulasLandmark(
      id: 'police_station_3',
      routingAvailable: false, // Current station identity/entrance unconfirmed.
      quickCategories: {QuickDestinationCategory.emergencyServices},
      name: 'Valenzuela Police Sub-Station 3 (Marulas)',
      category: 'Police / Emergency',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6762,
      lng: 120.9848,
      icon: Icons.local_police,
      tags: [
        'police',
        'pnp',
        'station',
        'substation',
        'security',
        'emergency',
        'cop',
        'pio valenzuela',
      ],
    ),
    MarulasLandmark(
      id: 'fire_station_marulas',
      routingAvailable: false, // Catalog address/pin not corroborated.
      quickCategories: {QuickDestinationCategory.emergencyServices},
      name: 'Valenzuela Fire Sub-Station (Marulas)',
      category: 'Fire / Emergency',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6780,
      lng: 120.9792,
      icon: Icons.fire_hydrant_alt,
      tags: [
        'fire',
        'bfp',
        'bumbero',
        'station',
        'fire station',
        'emergency',
        'macarthur',
      ],
    ),
    MarulasLandmark(
      id: 'marulas_gym',
      name: 'Marulas Multi-Purpose Covered Court / Gym',
      category: 'Sports / Community',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6767,
      lng: 120.9843,
      icon: Icons.sports_basketball,
      tags: [
        'court',
        'gym',
        'gymnasium',
        'basketball',
        'covered court',
        'complex',
        'pio valenzuela',
      ],
    ),

    // --- Churches & Religious Sites ---
    MarulasLandmark(
      id: 'san_ildefonso_church',
      name: 'San Ildefonso Parish Church',
      category: 'Church / Worship',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6772,
      lng: 120.9838,
      icon: Icons.church,
      tags: [
        'church',
        'parish',
        'san ildefonso',
        'simbahan',
        'catholic',
        'pio valenzuela',
      ],
    ),
    MarulasLandmark(
      id: 'fatima_shrine',
      name: 'National Shrine of Our Lady of Fatima',
      category: 'Church / Worship',
      address: 'MacArthur Highway cor. Fatima Ave, Marulas, Valenzuela',
      lat: 14.6786,
      lng: 120.9784,
      icon: Icons.church,
      tags: [
        'fatima shrine',
        'shrine',
        'our lady of fatima',
        'church',
        'basilica',
        'simbahan',
        'macarthur',
      ],
    ),
    MarulasLandmark(
      id: 'inc_marulas',
      name: 'Iglesia Ni Cristo - Lokal ng Marulas',
      category: 'Church / Worship',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6755,
      lng: 120.9855,
      icon: Icons.church,
      tags: ['inc', 'iglesia ni cristo', 'kapilya', 'church', 'pio valenzuela'],
    ),
    MarulasLandmark(
      id: 'san_lorenzo_chapel',
      name: 'San Lorenzo Ruiz Chapel',
      category: 'Church / Worship',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6769,
      lng: 120.9841,
      icon: Icons.church,
      tags: ['san lorenzo', 'chapel', 'kapilya', 'church', 'ruiz'],
    ),

    // --- Markets, Malls, Supermarkets & Food ---
    MarulasLandmark(
      id: 'marulas_market',
      name: 'Marulas Public Market (Palengke)',
      category: 'Market / Shopping',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6775,
      lng: 120.9790,
      icon: Icons.storefront,
      tags: [
        'market',
        'palengke',
        'public market',
        'pamilihan',
        'macarthur',
        'groceries',
      ],
    ),
    MarulasLandmark(
      id: 'savemore_marulas',
      name: 'SM Savemore Market Marulas',
      category: 'Supermarket / Shopping',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6783,
      lng: 120.9794,
      icon: Icons.shopping_cart,
      tags: [
        'savemore',
        'sm',
        'supermarket',
        'groceries',
        'macarthur',
        'shopping',
      ],
    ),
    MarulasLandmark(
      id: 'puregold_jr_marulas',
      name: 'Puregold Jr. Marulas',
      category: 'Supermarket / Shopping',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6778,
      lng: 120.9796,
      icon: Icons.shopping_bag,
      tags: ['puregold', 'supermarket', 'groceries', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'south_supermarket',
      name: 'South Supermarket Valenzuela',
      category: 'Supermarket / Shopping',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6792,
      lng: 120.9780,
      icon: Icons.shopping_cart,
      tags: ['south', 'supermarket', 'groceries', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'jollibee_fatima',
      name: 'Jollibee - Fatima MacArthur',
      category: 'Food / Fast Food',
      address: 'MacArthur Highway cor. Fatima Ave, Marulas, Valenzuela',
      lat: 14.6785,
      lng: 120.9787,
      icon: Icons.fastfood,
      tags: [
        'jollibee',
        'fastfood',
        'food',
        'restaurant',
        'chickenjoy',
        'fatima',
        'macarthur',
      ],
    ),
    MarulasLandmark(
      id: 'mcdonalds_fatima',
      name: "McDonald's - Fatima MacArthur",
      category: 'Food / Fast Food',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6787,
      lng: 120.9789,
      icon: Icons.fastfood,
      tags: [
        'mcdo',
        'mcdonalds',
        'fastfood',
        'burger',
        'fries',
        'macarthur',
        'fatima',
      ],
    ),
    MarulasLandmark(
      id: 'chowking_fatima',
      name: 'Chowking - Fatima MacArthur',
      category: 'Food / Fast Food',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6789,
      lng: 120.9785,
      icon: Icons.restaurant,
      tags: ['chowking', 'chinese', 'fastfood', 'fatima', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'seven_eleven_fatima',
      name: '7-Eleven - Fatima MacArthur',
      category: 'Convenience Store',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6784,
      lng: 120.9786,
      icon: Icons.local_convenience_store,
      tags: ['7-eleven', '711', 'convenience', 'store', 'fatima', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'seven_eleven_pio',
      name: '7-Eleven - Pio Valenzuela',
      category: 'Convenience Store',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6766,
      lng: 120.9846,
      icon: Icons.local_convenience_store,
      tags: ['7-eleven', '711', 'convenience', 'store', 'pio valenzuela'],
    ),
    MarulasLandmark(
      id: 'alfamart_pio',
      name: 'Alfamart - Pio Valenzuela',
      category: 'Convenience Store',
      address: 'Pio Valenzuela St, Marulas, Valenzuela',
      lat: 14.6761,
      lng: 120.9850,
      icon: Icons.local_convenience_store,
      tags: ['alfamart', 'convenience', 'store', 'groceries', 'pio valenzuela'],
    ),

    // --- Key Intersections, Gas Stations & Boundaries ---
    MarulasLandmark(
      id: 'pio_macarthur_junction',
      name: 'Pio Valenzuela & MacArthur Highway Junction',
      category: 'Intersection / Highway',
      address: 'Junction of Pio Valenzuela St & MacArthur Hwy, Marulas',
      lat: 14.6781,
      lng: 120.9789,
      icon: Icons.alt_route,
      tags: [
        'junction',
        'corner',
        'pio valenzuela',
        'macarthur',
        'intersection',
        'crossing',
      ],
    ),
    MarulasLandmark(
      id: 'tullahan_bridge',
      name: 'Tullahan River Bridge (Marulas - Monumento Boundary)',
      category: 'Bridge / Boundary',
      address: 'MacArthur Highway, Marulas, Valenzuela City',
      lat: 14.6728,
      lng: 120.9805,
      icon: Icons.water,
      tags: [
        'tullahan',
        'bridge',
        'river',
        'boundary',
        'monumento',
        'macarthur',
      ],
    ),
    MarulasLandmark(
      id: 'karuhatan_boundary',
      name: 'Karuhatan - Marulas Boundary (MacArthur Hwy)',
      category: 'Boundary / Highway',
      address: 'MacArthur Highway (Near BBB), Marulas, Valenzuela',
      lat: 14.6810,
      lng: 120.9770,
      icon: Icons.timeline,
      tags: [
        'karuhatan',
        'boundary',
        'bbb',
        'macarthur highway',
        'north bound',
      ],
    ),
    MarulasLandmark(
      id: 'shell_macarthur',
      name: 'Shell Gas Station - MacArthur Marulas',
      category: 'Gas Station / Services',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6790,
      lng: 120.9782,
      icon: Icons.local_gas_station,
      tags: ['shell', 'gas', 'gas station', 'fuel', 'petrol', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'petron_macarthur',
      name: 'Petron Gas Station - MacArthur Marulas',
      category: 'Gas Station / Services',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6770,
      lng: 120.9798,
      icon: Icons.local_gas_station,
      tags: ['petron', 'gas', 'gas station', 'fuel', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'caltex_macarthur',
      name: 'Caltex Gas Station - MacArthur Marulas',
      category: 'Gas Station / Services',
      address: 'MacArthur Highway, Marulas, Valenzuela',
      lat: 14.6755,
      lng: 120.9801,
      icon: Icons.local_gas_station,
      tags: ['caltex', 'gas', 'gas station', 'fuel', 'macarthur'],
    ),
    MarulasLandmark(
      id: 'serrano_subdivision',
      name: 'Serrano Subdivision Gate',
      category: 'Subdivision / Residential',
      address: 'Serrano St, Marulas, Valenzuela',
      lat: 14.6745,
      lng: 120.9820,
      icon: Icons.home,
      tags: ['serrano', 'subdivision', 'gate', 'residential', 'village'],
    ),
    MarulasLandmark(
      id: 'constantino_subdivision',
      name: 'Constantino Subdivision',
      category: 'Subdivision / Residential',
      address: 'Constantino Village, Marulas, Valenzuela',
      lat: 14.6725,
      lng: 120.9800,
      icon: Icons.home,
      tags: ['constantino', 'village', 'subdivision', 'residential'],
    ),
  ];

  /// Match every meaningful query word; catalog pins still need entrance review.
  static List<MarulasLandmark> search(
    String query, {
    Iterable<MarulasLandmark>? landmarks,
  }) {
    final results = (landmarks ?? all)
        .where(
          (place) =>
              place.routingAvailable &&
              place.lat.isFinite &&
              place.lng.isFinite &&
              place.lat.abs() <= 90 &&
              place.lng.abs() <= 180 &&
              matchesPlaceSearch(query, [
                place.name,
                place.category,
                place.address,
                ...place.tags,
              ], ignoreAreaWords: true),
        )
        .toList();
    final wanted = placeSearchWords(query, ignoreAreaWords: true).join(' ');
    int rank(MarulasLandmark place) {
      final name = placeSearchWords(
        place.name,
        ignoreAreaWords: true,
      ).join(' ');
      return name == wanted
          ? 0
          : name.startsWith(wanted)
          ? 1
          : 2;
    }

    results.sort((a, b) {
      final priority = rank(a).compareTo(rank(b));
      return priority != 0 ? priority : a.name.compareTo(b.name);
    });
    return results;
  }

  /// Popular quick-pick landmarks for 1-tap route planning representing distinct geographic zones of Marulas.
  static List<MarulasLandmark> get popularQuickPicks => [
    all.firstWhere(
      (l) => l.id == 'olfu_main',
    ), // Northwest - MacArthur Corridor
    all.firstWhere(
      (l) => l.id == 'marulas_brgy_hall',
    ), // Central - Pio Valenzuela St
    all.firstWhere(
      (l) => l.id == 'marulas_elem_school',
    ), // South-Central - Serrano St / Evac Center
    all.firstWhere(
      (l) => l.id == 'tullahan_bridge',
    ), // South Boundary - Tullahan River / Monumento Gate
    all.firstWhere(
      (l) => l.id == 'karuhatan_boundary',
    ), // North Boundary - BBB / Karuhatan Gate
    all.firstWhere(
      (l) => l.id == 'constantino_subdivision',
    ), // Southwest - Constantino Residential Zone
    all.firstWhere(
      (l) => l.id == 'st_bernadette_academy',
    ), // East Interior - P. Gomez St
  ].where((place) => place.routingAvailable).toList();
}
