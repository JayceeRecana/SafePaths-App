import 'package:flutter_test/flutter_test.dart';
import 'package:safepaths_app/config/risk_config.dart';
import 'package:safepaths_app/models/road_status.dart';
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/services/risk_engine.dart';
import 'package:safepaths_app/services/weather_service.dart';

// ─── Helper Factory ────────────────────────────────────────────────────────────

RoadStatus makeRoad({
  required String id,
  required String status,
  String name = 'Test St',
  String vulnerability = 'low',
  List<String> neighbors = const [],
  DateTime? updatedAt,
}) =>
    RoadStatus(
      id: id,
      name: name,
      status: status,
      notes: '',
      updatedAt: updatedAt ?? DateTime(2026, 6, 1, 12, 0),
      vulnerability: vulnerability,
      neighbors: neighbors,
    );

UserReport makeReport({
  required String id,
  required String userId,
  required String roadId,
  required String severity,
  required DateTime createdAt,
  double authorityScore = 50.0,
  String status = 'pending',
}) =>
    UserReport(
      id: id,
      title: 'Flooding',
      description: 'Road flooded',
      createdAt: createdAt,
      severity: severity,
      status: status,
      roadId: roadId,
      userId: userId,
      authorityScore: authorityScore,
    );

void main() {
  // ─── Threshold Tests ────────────────────────────────────────────────────────
  group('Risk Engine Threshold Tests', () {
    String getCategory(double finalScore) {
      if (finalScore >= RiskConfig.warningThreshold) return 'Critical';
      if (finalScore >= RiskConfig.watchThreshold) return 'Warning';
      if (finalScore >= RiskConfig.safeThreshold) return 'Watch';
      return 'Safe';
    }

    test('Score 29 should be Safe', () => expect(getCategory(29.0), 'Safe'));
    test('Score 30 should be Watch', () => expect(getCategory(30.0), 'Watch'));
    test('Score 59.9 should be Watch', () => expect(getCategory(59.9), 'Watch'));
    test('Score 60 should be Warning', () => expect(getCategory(60.0), 'Warning'));
    test('Score 79.9 should be Warning', () => expect(getCategory(79.9), 'Warning'));
    test('Score 80 should be Critical', () => expect(getCategory(80.0), 'Critical'));
    test('Score 100 should be Critical', () => expect(getCategory(100.0), 'Critical'));
  });

  // ─── RiskEngine.calculateRoadRisk Pure Function Tests ──────────────────────
  group('RiskEngine.calculateRoadRisk — pure function & DI time travel', () {
    final baseTime = DateTime(2026, 6, 1, 12, 0);

    test('Passable road with no neighbors and no reports → 0 risk (Safe)', () {
      final road = makeRoad(id: 'r1', status: 'passable', updatedAt: baseTime);
      final result = RiskEngine.calculateRoadRisk(
        road: road,
        allRoads: [road],
        pendingReports: [],
        weatherState: WeatherState.clear,
        currentTime: baseTime,
      );
      expect(result.finalScore, 0.0);
      expect(result.riskCategory, 'Safe');
      expect(result.baseRisk, 0.0);
      expect(result.consensusRisk, 0.0);
      expect(result.propagationRisk, 0.0);
    });

    test('not_passable road → 100 base risk (Critical)', () {
      final road = makeRoad(id: 'r2', status: 'not_passable', updatedAt: baseTime);
      final result = RiskEngine.calculateRoadRisk(
        road: road,
        allRoads: [road],
        pendingReports: [],
        weatherState: WeatherState.clear,
        currentTime: baseTime,
      );
      expect(result.baseRisk, 100.0);
      expect(result.finalScore, 100.0);
      expect(result.riskCategory, 'Critical');
    });

    test('partial road → 50 base risk (Watch)', () {
      final road = makeRoad(id: 'r3', status: 'partial', updatedAt: baseTime);
      final result = RiskEngine.calculateRoadRisk(
        road: road,
        allRoads: [road],
        pendingReports: [],
        weatherState: WeatherState.clear,
        currentTime: baseTime,
      );
      expect(result.baseRisk, 50.0);
      expect(result.finalScore, 50.0);
      expect(result.riskCategory, 'Watch');
    });

    test('Propagation from high-risk neighbor under heavy rain (high vulnerability)', () {
      final neighbor = makeRoad(id: 'flooded', status: 'not_passable', updatedAt: baseTime);
      final target = makeRoad(
        id: 'target',
        status: 'passable',
        vulnerability: 'high',
        neighbors: ['flooded'],
        updatedAt: baseTime,
      );

      final result = RiskEngine.calculateRoadRisk(
        road: target,
        allRoads: [target, neighbor],
        pendingReports: [],
        weatherState: WeatherState.heavyRain,
        previousRisks: {'flooded': 100.0},
        currentTime: baseTime,
      );

      // heavyRain multiplier = 0.7, high vulnerability = 1.0, neighbor risk = 100
      // propagation = min(100 * 0.7 * 1.0, 100 * 0.95) = min(70, 95) = 70
      expect(result.propagationRisk, closeTo(70.0, 0.5));
      expect(result.propagationSource, 'flooded');
      // 70 >= watchThreshold(60) → Warning category
      expect(result.riskCategory, anyOf('Warning', 'Critical'));
    });

    test('Time escalation activates only when score >= watchThreshold (60)', () {
      // Use not_passable (base=100) so timer activates at t=0
      final road = makeRoad(id: 'r_warn', status: 'not_passable', updatedAt: baseTime);

      // 10 min — no 30-min or 60-min bonus yet (< 30 min)
      var res = RiskEngine.calculateRoadRisk(
        road: road, allRoads: [road], pendingReports: [],
        weatherState: WeatherState.clear,
        currentTime: baseTime.add(const Duration(minutes: 10)),
      );
      expect(res.timeBonus, 0.0);
      expect(res.finalScore, 100.0); // clamped at 100

      // 35 min — 30-minute bonus applies
      res = RiskEngine.calculateRoadRisk(
        road: road, allRoads: [road], pendingReports: [],
        weatherState: WeatherState.clear,
        currentTime: baseTime.add(const Duration(minutes: 35)),
      );
      expect(res.timeBonus, RiskConfig.warning30MinuteBonus);
      expect(res.riskCategory, 'Critical'); // 100 clamped → Critical

      // 65 min — 60-minute bonus applies
      res = RiskEngine.calculateRoadRisk(
        road: road, allRoads: [road], pendingReports: [],
        weatherState: WeatherState.clear,
        currentTime: baseTime.add(const Duration(minutes: 65)),
      );
      expect(res.timeBonus, RiskConfig.warning60MinuteBonus);
      expect(res.riskCategory, 'Critical'); // 100 clamped → Critical
    });

    test('Stale prediction window: beyond max minutes → -20 decay', () {
      // Use not_passable (base=100) to ensure timer is active for decay
      final road = makeRoad(id: 'r_decay', status: 'not_passable', updatedAt: baseTime);
      final res = RiskEngine.calculateRoadRisk(
        road: road, allRoads: [road], pendingReports: [],
        weatherState: WeatherState.clear,
        currentTime: baseTime.add(Duration(minutes: RiskConfig.predictionWindowMinutes + 5)),
      );
      expect(res.timeBonus, -20.0);
      // 100 base - 20 decay = 80 → Warning boundary
      expect(res.finalScore, closeTo(80.0, 0.1));
      expect(res.riskCategory, anyOf('Warning', 'Critical'));
    });
  });

  // ─── Confidence Breakdown Tests ────────────────────────────────────────────
  group('RiskEngine.calculateLiveConfidenceBreakdown — consensus & Sybil tests', () {
    final baseTime = DateTime(2026, 6, 1, 12, 0);
    final testRoad = makeRoad(id: 'road_target', status: 'passable', updatedAt: baseTime);

    test('Authority-100 reporter at t=0 → 70 confidence (50 authority + 20 recency)', () {
      final report = makeReport(
        id: 'rep_1', userId: 'official', roadId: 'road_target',
        severity: 'High', createdAt: baseTime, authorityScore: 100.0,
      );
      final bd = RiskEngine.calculateLiveConfidenceBreakdown(
        report: report,
        allRoads: [testRoad],
        pendingReports: [report],
        weatherState: WeatherState.clear,
        currentTime: baseTime,
      );
      expect(bd['authorityContribution'], 50.0);  // 100 * 0.5
      expect(bd['recencyContribution'], 20.0);     // 100 * 0.2
      expect(bd['total'], 70.0);
    });

    test('Trusted neighbor confirming same severity → consensus boosted by full authority weight', () {
      final mainReport = makeReport(
        id: 'r1', userId: 'u1', roadId: 'road_target',
        severity: 'High', createdAt: baseTime, authorityScore: 60.0,
      );
      final trusted = makeReport(
        id: 'r2', userId: 'u2', roadId: 'road_target',
        severity: 'High',
        createdAt: baseTime.add(const Duration(minutes: 5)),
        authorityScore: 100.0, // weight = 1.0
      );
      final bd = RiskEngine.calculateLiveConfidenceBreakdown(
        report: mainReport,
        allRoads: [testRoad],
        pendingReports: [mainReport, trusted],
        weatherState: WeatherState.clear,
        currentTime: baseTime.add(const Duration(minutes: 5)),
      );
      // Consensus = 50 + 25 * 1.0 = 75
      expect(bd['consensus'], 75.0);
      expect(bd['total'] > 50.0, true);
    });

    test('Sybil attack: low-authority bot (score=20) adds only 5 pts consensus vs 25 pts for legit', () {
      final mainReport = makeReport(
        id: 'r1', userId: 'u1', roadId: 'road_target',
        severity: 'High', createdAt: baseTime, authorityScore: 50.0,
      );
      final botReport = makeReport(
        id: 'r_bot', userId: 'bot_1', roadId: 'road_target',
        severity: 'High',
        createdAt: baseTime.add(const Duration(minutes: 2)),
        authorityScore: 20.0, // clamped weight = 0.2 → 25 * 0.2 = 5.0
      );
      final bd = RiskEngine.calculateLiveConfidenceBreakdown(
        report: mainReport,
        allRoads: [testRoad],
        pendingReports: [mainReport, botReport],
        weatherState: WeatherState.clear,
        currentTime: baseTime.add(const Duration(minutes: 2)),
      );
      // Consensus = 50 + 25 * 0.2 = 55
      expect(bd['consensus'], 55.0);
    });

    test('Reports older than decay window produce 0 recency contribution', () {
      // Default clear weather decay = 12 hours
      final staleReport = makeReport(
        id: 'r_stale', userId: 'u1', roadId: 'road_target',
        severity: 'High',
        createdAt: baseTime.subtract(const Duration(hours: 13)),
        authorityScore: 50.0,
      );
      final bd = RiskEngine.calculateLiveConfidenceBreakdown(
        report: staleReport,
        allRoads: [testRoad],
        pendingReports: [staleReport],
        weatherState: WeatherState.clear,
        currentTime: baseTime,
      );
      expect(bd['recencyContribution'], 0.0);
    });

    test('Heavy rain extends decay window → older report still has recency score', () {
      // Under heavy rain, decay window = 28 hours
      // A report 13 hours old should still have positive recency
      final report = makeReport(
        id: 'r_hw', userId: 'u1', roadId: 'road_target',
        severity: 'High',
        createdAt: baseTime.subtract(const Duration(hours: 13)),
        authorityScore: 50.0,
      );
      final bd = RiskEngine.calculateLiveConfidenceBreakdown(
        report: report,
        allRoads: [testRoad],
        pendingReports: [report],
        weatherState: WeatherState.heavyRain,
        currentTime: baseTime,
      );
      expect(bd['recencyContribution'] > 0.0, true);
    });
  });

  // ─── Weather Multiplier Tests ──────────────────────────────────────────────
  group('RiskConfig.getWeatherMultiplier — centralized multiplier', () {
    test('Clear weather → multiplier 0.0', () {
      expect(RiskConfig.getWeatherMultiplier(WeatherState.clear), 0.0);
    });

    test('Light rain → multiplier > 0', () {
      expect(RiskConfig.getWeatherMultiplier(WeatherState.lightRain) > 0, true);
    });

    test('Typhoon → highest multiplier', () {
      final typhoon = RiskConfig.getWeatherMultiplier(WeatherState.typhoon);
      final heavy = RiskConfig.getWeatherMultiplier(WeatherState.heavyRain);
      expect(typhoon > heavy, true);
    });

    test('Heavy rain multiplier < typhoon multiplier', () {
      final heavy = RiskConfig.getWeatherMultiplier(WeatherState.heavyRain);
      final typhoon = RiskConfig.getWeatherMultiplier(WeatherState.typhoon);
      expect(heavy, lessThan(typhoon));
    });
  });
}
