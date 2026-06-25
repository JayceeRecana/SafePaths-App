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
  static const double passableStaleThresholdHours = 0.01; // Quick threshold for demo
  
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
