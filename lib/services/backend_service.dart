import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

/// Firebase callable protocol. Privileged credentials never enter the app.
class BackendService {
  static Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in and try again.');
    final token = await user.getIdToken();
    final project = Firebase.app().options.projectId;
    final response = await http
        .post(
          Uri.https('us-central1-$project.cloudfunctions.net', '/$name'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || decoded['error'] != null) {
      final error = decoded['error'] as Map?;
      throw StateError(
        error?['message'] as String? ?? 'Server unavailable. Please retry.',
      );
    }
    return Map<String, dynamic>.from(
      decoded['result'] as Map? ?? decoded['data'] as Map? ?? {},
    );
  }
}
