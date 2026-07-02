class RiskConfig {
  // Categorization Thresholds
  static const double safeThreshold = 30.0;
  static const double watchThreshold = 60.0;
  static const double warningThreshold = 80.0;

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
  
  // Time-to-Risk Escalation Bonuses
  static const double warning30MinuteBonus = 10.0;
  static const double warning60MinuteBonus = 20.0;

  // Flood Cluster Constraints
  static const int floodClusterMinimumRoads = 3;
  static const double floodClusterMinimumAverageRisk = 70.0;
  
  // Route Cost Penalties
  static const double averageRiskWeight = 5.0; 
  static const double criticalSegmentWeight = 50.0;
}