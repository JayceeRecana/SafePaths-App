class UserProfile {
  final String id;
  final String name;
  final String email;
  final String location;
  final String role;
  final int trustScore;
  final int verifiedReports;
  final int dismissedReports;
  final String? photoUrl;

  UserProfile({
    required this.id,
    this.name = 'Resident',
    this.email = 'No Email',
    this.location = 'Brgy. Marulas',
    this.role = 'user',
    this.trustScore = 50,
    this.verifiedReports = 0,
    this.dismissedReports = 0,
    this.photoUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'location': location,
        'role': role,
        'trustScore': trustScore,
        'verifiedReports': verifiedReports,
        'dismissedReports': dismissedReports,
        if (photoUrl != null) 'photoUrl': photoUrl,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Resident',
      email: json['email'] ?? 'No Email',
      location: json['location'] ?? 'Brgy. Marulas',
      role: json['role'] ?? 'user',
      trustScore: json['trustScore'] ?? 50,
      verifiedReports: json['verifiedReports'] ?? 0,
      dismissedReports: json['dismissedReports'] ?? 0,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  UserProfile copyWith({
    String? name,
    String? email,
    String? location,
    String? role,
    int? trustScore,
    int? verifiedReports,
    int? dismissedReports,
    String? photoUrl,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      location: location ?? this.location,
      role: role ?? this.role,
      trustScore: trustScore ?? this.trustScore,
      verifiedReports: verifiedReports ?? this.verifiedReports,
      dismissedReports: dismissedReports ?? this.dismissedReports,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  static int getTrustLevel(int score) {
    if (score >= 80) return 5;
    if (score >= 60) return 4;
    if (score >= 40) return 3;
    if (score >= 20) return 2;
    return 1;
  }
}
