import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Display/awareness only. Deliberately has no reporting, weather, risk-engine,
// road-status, authentication, database or routing dependency.
class NoahPoint {
  final double x, y;
  const NoahPoint(this.x, this.y);
}

class NoahBounds {
  final double west, south, east, north;
  const NoahBounds(this.west, this.south, this.east, this.north);
  bool contains(NoahPoint p) =>
      p.x >= west && p.x <= east && p.y >= south && p.y <= north;
  bool overlaps(NoahBounds b) =>
      west <= b.east && east >= b.west && south <= b.north && north >= b.south;
  factory NoahBounds.points(Iterable<NoahPoint> points) {
    final p = points.toList();
    return NoahBounds(
      p.map((p) => p.x).reduce(math.min),
      p.map((p) => p.y).reduce(math.min),
      p.map((p) => p.x).reduce(math.max),
      p.map((p) => p.y).reduce(math.max),
    );
  }
}

class NoahAssessment {
  final Set<int> levels;
  final bool available, partial;
  final NoahLengthBreakdown? lengthBreakdown;
  const NoahAssessment({
    this.levels = const {},
    this.available = false,
    this.partial = false,
    this.lengthBreakdown,
  });
}

enum NoahLengthCategory { high, medium, low, noMappedHazard, outsidePrepared }

/// A display calculation over the whole unique mapped centreline, not a flood
/// probability, observed depth, or a passability/routing input.
class NoahLengthBreakdown {
  final Map<NoahLengthCategory, double> meters;
  final double totalMeters;
  NoahLengthBreakdown._(Map<NoahLengthCategory, double> values)
    : meters = Map.unmodifiable(values),
      totalMeters = values.values.fold(0, (a, b) => a + b);
  double fraction(NoahLengthCategory category) =>
      (meters[category] ?? 0) / totalMeters;
  // Largest remainder rounding: the five displayed shares total 100.0%.
  late final Map<NoahLengthCategory, int> tenthsPercent = _round();
  Map<NoahLengthCategory, int> _round() {
    final result = <NoahLengthCategory, int>{},
        remainders = <NoahLengthCategory, double>{};
    for (final c in NoahLengthCategory.values) {
      final exact = fraction(c) * 1000;
      result[c] = exact.floor();
      remainders[c] = exact - exact.floor();
    }
    final order = [...NoahLengthCategory.values]
      ..sort((a, b) {
        final diff = remainders[b]!.compareTo(remainders[a]!);
        return diff == 0 ? a.index.compareTo(b.index) : diff;
      });
    var left = 1000 - result.values.fold(0, (a, b) => a + b), i = 0;
    while (left > 0) {
      final c = order[i++ % order.length];
      result[c] = result[c]! + 1;
      left--;
    }
    while (left < 0) {
      final c = order.reversed.toList()[i++ % order.length];
      if (result[c]! > 0) {
        result[c] = result[c]! - 1;
        left++;
      }
    }
    return Map.unmodifiable(result);
  }
}

class _Polygon {
  final int level;
  final List<List<NoahPoint>> rings;
  late final NoahBounds bounds = NoahBounds.points(rings.first);
  _Polygon(this.level, this.rings);
  bool contains(NoahPoint p) =>
      bounds.contains(p) &&
      _inRing(p, rings.first) &&
      !rings.skip(1).any((r) => _inRing(p, r));
  bool covers(NoahPoint p) =>
      bounds.contains(p) &&
      (contains(p) ||
          rings.any((r) => _edges(r).any((e) => _on(e.$1, e.$2, p))));
  bool crosses(NoahPoint a, NoahPoint b) =>
      bounds.overlaps(NoahBounds.points([a, b])) &&
      (contains(a) ||
          contains(b) ||
          rings.any(
            (r) => _edges(r).any((edge) => _cross(a, b, edge.$1, edge.$2)),
          ));
}

Iterable<(NoahPoint, NoahPoint)> _edges(List<NoahPoint> r) sync* {
  for (var i = 0; i < r.length; i++) {
    yield (r[i], r[(i + 1) % r.length]);
  }
}

double _orientation(NoahPoint a, NoahPoint b, NoahPoint c) =>
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
bool _on(NoahPoint a, NoahPoint b, NoahPoint p) =>
    _orientation(a, b, p).abs() < 1e-12 &&
    p.x >= math.min(a.x, b.x) - 1e-10 &&
    p.x <= math.max(a.x, b.x) + 1e-10 &&
    p.y >= math.min(a.y, b.y) - 1e-10 &&
    p.y <= math.max(a.y, b.y) + 1e-10;
bool _cross(NoahPoint a, NoahPoint b, NoahPoint c, NoahPoint d) {
  final abC = _orientation(a, b, c),
      abD = _orientation(a, b, d),
      cdA = _orientation(c, d, a),
      cdB = _orientation(c, d, b);
  return ((abC > 0 && abD < 0 || abC < 0 && abD > 0) &&
          (cdA > 0 && cdB < 0 || cdA < 0 && cdB > 0)) ||
      _on(a, b, c) ||
      _on(a, b, d) ||
      _on(c, d, a) ||
      _on(c, d, b);
}

bool _inRing(NoahPoint p, List<NoahPoint> r) {
  var inside = false;
  for (final (a, b) in _edges(r)) {
    if (_on(a, b, p)) return true;
    if ((a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x)
      inside = !inside;
  }
  return inside;
}

NoahPoint _point(dynamic v) {
  if (v is! List || v.length < 2 || v[0] is! num || v[1] is! num)
    throw const FormatException('Invalid coordinates');
  final p = NoahPoint((v[0] as num).toDouble(), (v[1] as num).toDouble());
  if (!p.x.isFinite || !p.y.isFinite || p.x.abs() > 180 || p.y.abs() > 90)
    throw const FormatException('Invalid coordinates');
  return p;
}

NoahPoint _at(NoahPoint a, NoahPoint b, double t) =>
    NoahPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
double _parameter(NoahPoint a, NoahPoint b, NoahPoint p) {
  final x = b.x - a.x, y = b.y - a.y;
  return ((p.x - a.x) * x + (p.y - a.y) * y) / (x * x + y * y);
}

double _meters(NoahPoint a, NoahPoint b) {
  const rad = math.pi / 180;
  final lat1 = a.y * rad, lat2 = b.y * rad;
  final h =
      math.pow(math.sin((lat2 - lat1) / 2), 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.pow(math.sin((b.x - a.x) * rad / 2), 2);
  return 6371008.8 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
}

// Remove repeated/reversed and partially overlapping collinear centreline
// pieces, so duplicated MultiLineString pieces do not inflate the denominator.
List<(NoahPoint, NoahPoint)> _uniqueRoadSegments(
  List<(NoahPoint, NoahPoint)> input,
) {
  final accepted = <(NoahPoint, NoahPoint)>[];
  for (final (a, b) in input) {
    if ((b.x - a.x).abs() > 180)
      throw const FormatException('Unsupported dateline segment');
    if (_meters(a, b) <= 1e-6) continue;
    final scale = math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
    final cuts = <(double, double)>[];
    for (final (c, d) in accepted) {
      if (_orientation(a, b, c).abs() / scale > 1e-10 ||
          _orientation(a, b, d).abs() / scale > 1e-10)
        continue;
      final tc = _parameter(a, b, c), td = _parameter(a, b, d);
      final lo = math.max(0.0, math.min(tc, td)),
          hi = math.min(1.0, math.max(tc, td));
      if (hi > lo) cuts.add((lo, hi));
    }
    cuts.sort((a, b) => a.$1.compareTo(b.$1));
    var cursor = 0.0;
    for (final (lo, hi) in cuts) {
      if (lo > cursor + 1e-12) accepted.add((_at(a, b, cursor), _at(a, b, lo)));
      cursor = math.max(cursor, hi);
    }
    if (cursor < 1 - 1e-12) accepted.add((_at(a, b, cursor), b));
  }
  return accepted;
}

void _splitAtEdge(
  NoahPoint a,
  NoahPoint b,
  NoahPoint c,
  NoahPoint d,
  List<double> cuts,
) {
  final rx = b.x - a.x, ry = b.y - a.y, sx = d.x - c.x, sy = d.y - c.y;
  final cross = rx * sy - ry * sx;
  final product = math.sqrt((rx * rx + ry * ry) * (sx * sx + sy * sy));
  if (product == 0) return;
  if (cross.abs() > product * 1e-14) {
    final t = ((c.x - a.x) * sy - (c.y - a.y) * sx) / cross;
    final u = ((c.x - a.x) * ry - (c.y - a.y) * rx) / cross;
    if (t >= -1e-10 && t <= 1 + 1e-10 && u >= -1e-10 && u <= 1 + 1e-10)
      cuts.add(t.clamp(0.0, 1.0));
  } else {
    final length = math.sqrt(rx * rx + ry * ry);
    if (_orientation(a, b, c).abs() / length > 1e-10) return;
    final tc = _parameter(a, b, c), td = _parameter(a, b, d);
    if (math.max(tc, td) < 0 || math.min(tc, td) > 1) return;
    cuts.add(tc.clamp(0.0, 1.0));
    cuts.add(td.clamp(0.0, 1.0));
  }
}

NoahLengthBreakdown? _roadLengths(
  List<(NoahPoint, NoahPoint)> segments,
  List<_Polygon> polygons,
  _Polygon extent,
) {
  final lengths = {for (final c in NoahLengthCategory.values) c: 0.0};
  for (final (a, b) in segments) {
    final segmentBounds = NoahBounds.points([a, b]);
    final candidates =
        polygons.where((p) => p.bounds.overlaps(segmentBounds)).toList()
          ..sort((a, b) => b.level.compareTo(a.level));
    final cuts = <double>[0, 1];
    for (final p in [extent, ...candidates]) {
      for (final ring in p.rings) {
        for (final edge in _edges(ring)) {
          _splitAtEdge(a, b, edge.$1, edge.$2, cuts);
        }
      }
    }
    cuts.sort();
    final unique = <double>[];
    for (final t in cuts) {
      if (unique.isEmpty || t - unique.last > 1e-12) unique.add(t);
    }
    final length = _meters(a, b);
    for (var i = 1; i < unique.length; i++) {
      final lo = unique[i - 1], hi = unique[i];
      final midpoint = _at(a, b, (lo + hi) / 2);
      var category = NoahLengthCategory.outsidePrepared;
      if (extent.covers(midpoint)) {
        category = NoahLengthCategory.noMappedHazard;
        for (final p in candidates) {
          if (p.covers(midpoint)) {
            // Highest mapped class wins overlaps for this display breakdown;
            // no part is counted twice, and no road status is modified.
            category = switch (p.level) {
              3 => NoahLengthCategory.high,
              2 => NoahLengthCategory.medium,
              _ => NoahLengthCategory.low,
            };
            break;
          }
        }
      }
      lengths[category] = lengths[category]! + length * (hi - lo);
    }
  }
  final result = NoahLengthBreakdown._(lengths);
  return result.totalMeters > 1e-6 && result.totalMeters.isFinite
      ? result
      : null;
}

class NoahDataset {
  final String geoJson;
  final NoahBounds bounds;
  final List<_Polygon> _polygons;
  NoahDataset._(this.geoJson, this.bounds, this._polygons);
  static NoahDataset parse(String raw) {
    final d = jsonDecode(raw) as Map<String, dynamic>;
    final m = d['metadata'] as Map;
    if (d['type'] != 'FeatureCollection' ||
        m['scenarioYears'] != 5 ||
        m['hasCoverageMask'] != false)
      throw const FormatException('Unexpected NOAH dataset');
    final b = (m['preparedBounds'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    if (b.length != 4 ||
        b.any((n) => !n.isFinite) ||
        b[0] >= b[2] ||
        b[1] >= b[3])
      throw const FormatException('Invalid bounds');
    final polygons = <_Polygon>[];
    for (final f in d['features'] as List) {
      final rawLevel = f['properties']['Var'] as num;
      final level = rawLevel.toInt();
      if (rawLevel != level || ![1, 2, 3].contains(level))
        throw const FormatException('Invalid hazard class');
      final g = f['geometry'] as Map;
      if (!['Polygon', 'MultiPolygon'].contains(g['type']))
        throw const FormatException('Invalid hazard geometry');
      final parts = g['type'] == 'Polygon'
          ? [g['coordinates']]
          : g['coordinates'] as List;
      for (final part in parts) {
        final rings = (part as List)
            .map((r) => (r as List).map(_point).toList())
            .toList();
        if (rings.isEmpty || rings.any((r) => r.length < 4))
          throw const FormatException('Invalid polygon');
        polygons.add(_Polygon(level, rings));
      }
    }
    if (polygons.isEmpty) throw const FormatException('Empty NOAH dataset');
    return NoahDataset._(raw, NoahBounds(b[0], b[1], b[2], b[3]), polygons);
  }

  NoahAssessment assess(Map<String, dynamic>? geometry) {
    try {
      if (geometry == null) return const NoahAssessment();
      final type = geometry['type'];
      if (type != 'LineString' && type != 'MultiLineString')
        return const NoahAssessment();
      // Firestore cannot store nested coordinate arrays. Imported roads retain
      // each disconnected way as a segment of latitude/longitude point maps.
      // Normalize only here; never flatten ways or alter stored road geometry.
      final dynamic rawLines;
      if (geometry.containsKey('segments')) {
        final segments = geometry['segments'] as List;
        rawLines = segments
            .map((segment) {
              final points = (segment as Map)['points'] as List;
              return points.map((point) {
                final p = point as Map;
                final coordinates = [p['lon'] ?? p['lng'], p['lat']];
                _point(
                  coordinates,
                ); // Validate before ignoring zero-length ways.
                return coordinates;
              }).toList();
            })
            .where((line) => line.length >= 2)
            .toList();
      } else {
        rawLines = type == 'LineString'
            ? [geometry['coordinates']]
            : geometry['coordinates'] as List;
      }
      final lines = (rawLines as List)
          .map((l) => (l as List).map(_point).toList())
          .toList();
      if (lines.isEmpty || lines.any((l) => l.length < 2))
        return const NoahAssessment();
      final extent = _Polygon(0, [
        [
          NoahPoint(bounds.west, bounds.south),
          NoahPoint(bounds.east, bounds.south),
          NoahPoint(bounds.east, bounds.north),
          NoahPoint(bounds.west, bounds.north),
        ],
      ]);
      final segments = _uniqueRoadSegments([
        for (final l in lines)
          for (var i = 1; i < l.length; i++) (l[i - 1], l[i]),
      ]);
      final breakdown = _roadLengths(segments, _polygons, extent);
      if (!segments.any((s) => extent.crosses(s.$1, s.$2)))
        return NoahAssessment(lengthBreakdown: breakdown);
      final levels = <int>{};
      for (final polygon in _polygons) {
        if (segments.any((s) => polygon.crosses(s.$1, s.$2)))
          levels.add(polygon.level);
      }
      return NoahAssessment(
        available: true,
        levels: Set.unmodifiable(levels),
        partial: lines.expand((l) => l).any((p) => !bounds.contains(p)),
        lengthBreakdown: breakdown,
      );
    } catch (_) {
      return const NoahAssessment();
    }
  }
}

enum NoahFailureStage { asset, data, render }

class NoahLoadException implements Exception {
  final NoahFailureStage stage;
  const NoahLoadException(this.stage);
  @override
  String toString() => 'NOAH loading failed (${stage.name})';
}

class NoahRepository {
  static Future<NoahDataset>? _pending;
  static Future<NoahDataset> load() => _pending ??= _load();
  static Future<NoahDataset> _load() async {
    try {
      return await loadAsset(rootBundle);
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }

  static Future<NoahDataset> loadAsset(AssetBundle bundle) async {
    final String raw;
    try {
      raw = await bundle.loadString('assets/noah/marulas-5year.geojson');
    } catch (_) {
      debugPrint('[NOAH] Bundled map data unavailable (asset).');
      throw const NoahLoadException(NoahFailureStage.asset);
    }
    try {
      return await compute(NoahDataset.parse, raw);
    } catch (_) {
      debugPrint('[NOAH] Bundled map data could not be decoded (data).');
      throw const NoahLoadException(NoahFailureStage.data);
    }
  }
}

class NoahMapController extends ChangeNotifier {
  final Future<NoahDataset> Function() load;
  bool safePaths = true, enabled = false, loading = false, failed = false;
  bool _disposed = false;
  NoahDataset? data;
  NoahFailureStage? failureStage;
  int renderAttempt = 0;
  NoahPoint? _center;
  bool? get centerInside =>
      data == null || _center == null ? null : data!.bounds.contains(_center!);
  void observeCenter(double longitude, double latitude) {
    final previous = centerInside;
    _center = NoahPoint(longitude, latitude);
    if (!_disposed && previous != centerInside) notifyListeners();
  }

  NoahMapController({Future<NoahDataset> Function()? loader})
    : load = loader ?? NoahRepository.load;
  void setSafePaths(bool value) {
    safePaths = value;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    failed = false;
    failureStage = null;
    notifyListeners();
    if (value && data == null) await retry();
  }

  Future<void> retry() async {
    if (loading || _disposed) return;
    loading = true;
    renderAttempt++;
    failed = false;
    failureStage = null;
    notifyListeners();
    try {
      final result = await load();
      if (!_disposed) data = result;
    } catch (error) {
      if (!_disposed) {
        failed = true;
        failureStage = error is NoahLoadException
            ? error.stage
            : NoahFailureStage.data;
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void renderFailed() {
    if (!_disposed && !failed) {
      failed = true;
      failureStage = NoahFailureStage.render;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
