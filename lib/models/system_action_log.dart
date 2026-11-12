class SystemActionLog {
  final DateTime timestamp;
  final String action;
  final String details;

  SystemActionLog({
    required this.timestamp,
    required this.action,
    required this.details,
  });
}
