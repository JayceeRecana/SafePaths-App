class AlertTemplate {
  final String id;
  final String label;
  final String title;
  final String message;
  final int severity;

  AlertTemplate({
    required this.id,
    required this.label,
    required this.title,
    required this.message,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'title': title,
        'message': message,
        'severity': severity,
      };

  factory AlertTemplate.fromJson(Map<String, dynamic> json) {
    return AlertTemplate(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      severity: json['severity'] ?? 0,
    );
  }
}
