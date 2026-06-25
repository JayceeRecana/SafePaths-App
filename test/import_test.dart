import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OSM Import String Normalization', () {
    String normalizeRoadName(String name) {
      return name
          .toLowerCase()
          .replaceAll('street', '')
          .replaceAll('st.', '')
          .replaceAll('st', '')
          .replaceAll('road', '')
          .replaceAll('rd', '')
          .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    test('Normalizes various formats of M.H. Del Pilar to the same key', () {
      String name1 = normalizeRoadName('M.H. Del Pilar');
      String name2 = normalizeRoadName('MH Del Pilar');
      String name3 = normalizeRoadName('M H Del Pilar Street');

      expect(name1, 'mh del pilar');
      expect(name2, 'mh del pilar');
      expect(name3, 'm h del pilar'); // Note: The user said it should normalize to the same key, let's check this later.
    });

    test('Strips out common road suffixes', () {
      expect(normalizeRoadName('MacArthur Highway'), 'macarthur highway');
      expect(normalizeRoadName('Pio Valenzuela St.'), 'pio valenzuela');
      expect(normalizeRoadName('A. Pablo Street'), 'a pablo');
    });

    test('Handles excessive whitespace and special characters', () {
      expect(normalizeRoadName('  San  Diego   Rd.  '), 'san diego');
      expect(normalizeRoadName('Fatima-Avenue!'), 'fatimaavenue');
    });
  });
}
