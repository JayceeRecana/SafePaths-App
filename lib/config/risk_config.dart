import '../services/weather_service.dart' show WeatherState;
import 'app_environment.dart';

class RiskConfig {
  // Categorization Thresholds
  static const double safeThreshold = 30.0;
  static const double watchThreshold = 60.0;
  static const double warningThreshold = 80.0;

  // Weather Multipliers (Single Source of Truth)
  static double getWeatherMultiplier(WeatherState state) {
    switch (state) {
      case WeatherState.clear:
      case WeatherState.partlyCloudy:
        return 0.0;
      case WeatherState.lightRain:
        return 0.2;
      case WeatherState.moderateRain:
        return 0.4;
      case WeatherState.heavyRain:
        return 0.7;
      case WeatherState.typhoon:
        return 1.0;
    }
  }

  static double getConfidenceWeatherMultiplier(WeatherState state) {
    if (state == WeatherState.clear) return 0.85;
    if (state == WeatherState.lightRain) return 1.05;
    if (state == WeatherState.moderateRain) return 1.10;
    if (state == WeatherState.heavyRain) return 1.15;
    if (state == WeatherState.typhoon) return 1.25;
    return 1.0;
  }

  // Topographical Vulnerability Multipliers
  static const double highVulnerability = 1.0;
  static const double mediumVulnerability = 0.5;
  static const double lowVulnerability = 0.2;

  // Temporal Decay & Expiration
  static const int predictionWindowMinutes = 120; // Predictions expire after 2 hours

  // Passable-Road Staleness Thresholds
  // Single source of truth for "how long can a road marked passable go without
  // reconfirmation before its status should be treated with suspicion."
  // Tiered by vulnerability since chronically flood-prone roads (e.g. Marulas
  // core / MacArthur Highway, tagged 'high') flood faster than less-exposed
  // roads — informed by Valenzuela City's own hourly situation-report cadence
  // and pumping-station priority list during active flood events.
  // Consumed by: RoadStatus.getEffectiveStatus, NavigationScreen route
  // staleness checks, RoutingService route safety evaluation, and the admin
  // "needs re-verification" list — kept identical across all four so the map,
  // navigation, routing, and admin views never disagree on the same road.
  static const double passableStaleThresholdHighVulnHours = 0.5;    // 30 min
  static const double passableStaleThresholdMediumVulnHours = 1.25; // 75 min
  static const double passableStaleThresholdLowVulnHours = 2.0;     // rarely hit — low-vuln roads aren't auto-downgraded

  static double getPassableStaleThresholdHours(String vulnerability) {
    switch (vulnerability) {
      case 'high':
        return passableStaleThresholdHighVulnHours;
      case 'medium':
        return passableStaleThresholdMediumVulnHours;
      default:
        return passableStaleThresholdLowVulnHours;
    }
  }

  // Admin Hazard Re-Check Cadence (Stagnant Flooded Road Inspection Thresholds)
  // Tiered by vulnerability: high-vulnerability flooded corridors prompt admin inspection
  // sooner than less-critical roads, avoiding admin alert fatigue while preventing forgotten hazards.
  static const double adminReCheckHighVulnHours = 3.0;
  static const double adminReCheckMediumVulnHours = 6.0;
  static const double adminReCheckLowVulnHours = 12.0;

  static double getAdminReCheckThresholdHours(String vulnerability) {
    switch (vulnerability) {
      case 'high':
        return adminReCheckHighVulnHours;
      case 'medium':
        return adminReCheckMediumVulnHours;
      default:
        return adminReCheckLowVulnHours;
    }
  }
  
  // Time-to-Risk Escalation Bonuses
  static const double warning30MinuteBonus = 10.0;
  static const double warning60MinuteBonus = 20.0;

  // Flood Cluster Constraints
  static const int floodClusterMinimumRoads = 3;
  static const double floodClusterMinimumAverageRisk = 70.0;
  
  // Route Cost Penalties
  static const double averageRiskWeight = 5.0; 
  static const double criticalSegmentWeight = 50.0;

  // Spatial Analysis & Road Crossing Buffers
  // Standardized buffer distance (in meters) to detect whether a route intersects a monitored road segment.
  // Calibration Rationale (35.0m):
  // Dense urban Marulas roads average 10-14m in width with smartphone GPS multipath jitter of ±10-15m.
  // 30m produced occasional false negatives on wide intersections or satellite drift.
  // 40m caused false positive bleed onto parallel residential alleys in subdivisions.
  // 35m is the calibrated sweet spot across both pre-trip planning and live navigation.
  static const double roadCrossingBufferMeters = 35.0;

  // Designated High-Ground Staging & Evacuation Centers (Barangay Marulas)
  // Used as fallback waypoints when a user's original destination is entirely cut off by impassable floods.
  static List<Map<String, dynamic>> get safeStagingFacilities => AppEnvironment.area.stagingFacilities;
}
