import 'dart:convert';
import 'dart:io';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/services/risk_engine.dart';
import 'package:safepaths_app/services/weather_service.dart';

void main() {
  final fixtures =
      jsonDecode(File('test/risk-parity-fixtures.json').readAsStringSync())
          as List;
  for (final fixture in fixtures) {
    test('server/Dart risk parity: ${fixture['name']}', () {
      final roads = (fixture['roads'] as List)
          .map(
            (r) => RoadStatus(
              id: r['id'],
              name: r['id'],
              status: r['status'],
              notes: '',
              updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updatedAt']),
              vulnerability: r['vulnerability'],
              neighbors: List<String>.from(r['neighbors']),
              riskScore: (r['riskScore'] as num).toDouble(),
              communityCondition: r['communityCondition'] as String?,
            ),
          )
          .toList();
      final reports = (fixture['reports'] as List)
          .map(
            (r) => UserReport(
              id: r['id'],
              userId: r['userId'],
              roadId: r['roadId'],
              title: 'Flood',
              reportType: r['reportType'] ?? 'original',
              incidentReviewStatus: r['incidentReviewStatus'],
              description: 'Water',
              status: r['status'],
              severity: r['severity'],
              authorityScore: (r['authorityScore'] as num).toDouble(),
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['createdAt']),
              observedAt: r['observedAt'] == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(r['observedAt']),
            ),
          )
          .toList();
      final weather = WeatherState.values.byName(fixture['weather']);
      for (var i = 0; i < roads.length; i++) {
        final actual = RiskEngine.calculateRoadRisk(
          road: roads[i],
          allRoads: roads,
          pendingReports: reports,
          weatherState: weather,
          currentTime: DateTime.fromMillisecondsSinceEpoch(fixture['now']),
        );
        final expected = fixture['expected'][i];
        expect(actual.finalScore, closeTo(expected['riskScore'], 0.0001));
        expect(actual.riskCategory, expected['riskCategory']);
        expect(
          actual.warningStartTime?.millisecondsSinceEpoch,
          expected['warningStartTime'],
        );
        expect(actual.propagationSource, expected['propagationSource']);
      }
    });
  }
}
