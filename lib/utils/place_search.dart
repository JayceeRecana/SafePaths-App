/// Prefix matching across words, without accepting only part of a longer query.
List<String> placeSearchWords(String text, {bool ignoreAreaWords = false}) {
  final normalized = text.toLowerCase().replaceAll('ñ', 'n');
  final words = RegExp(
    r'[a-z0-9]+',
  ).allMatches(normalized).map((m) => m.group(0)!).toList();
  if (!ignoreAreaWords) return words;
  const areaWords = {'marulas', 'valenzuela', 'city', 'brgy', 'barangay'};
  return words.where((word) => !areaWords.contains(word)).toList();
}

bool matchesPlaceSearch(
  String query,
  Iterable<String> fields, {
  bool ignoreAreaWords = false,
}) {
  final wanted = placeSearchWords(query, ignoreAreaWords: ignoreAreaWords);
  if (wanted.isEmpty) return false;
  final available = fields.expand((field) => placeSearchWords(field)).toList();
  return wanted.every((term) {
    final singular = term.endsWith('s') && term.length > 3
        ? term.substring(0, term.length - 1)
        : term;
    return available.any(
      (word) => word.startsWith(term) || word.startsWith(singular),
    );
  });
}
