/// Preserve provider names without deriving them from nearby intersecting roads.
List<String> roadNamesFromDirections(Map<String, dynamic> route) {
  final legs = route['legs'];
  if (legs is! List) return const [];
  final summaries = <String>{};
  final steps = <String>{};
  for (final leg in legs.whereType<Map>()) {
    final summary = leg['summary'];
    if (summary is String && summary.trim().isNotEmpty) {
      summaries.add(summary.trim());
    }
    final rawSteps = leg['steps'];
    if (rawSteps is! List) continue;
    for (final step in rawSteps.whereType<Map>()) {
      final name = step['name'];
      if (name is String && name.trim().isNotEmpty) steps.add(name.trim());
    }
  }
  return List.unmodifiable(summaries.isNotEmpty ? summaries : steps);
}
