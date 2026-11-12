import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_report_service.dart';
import '../config/app_environment.dart';

/// Serialized and sequence-checked so an old account cannot win a delayed save.
class PushDeviceRegistration {
  final String? Function() currentUid;
  final Future<Map<String, dynamic>?> Function() read;
  final Future<void> Function(Map<String, dynamic>) write;
  final Future<void> Function(Map<String, dynamic>) send;
  Future<void> _tail = Future.value();
  PushDeviceRegistration({
    required this.currentUid,
    required this.read,
    required this.write,
    required this.send,
  });
  factory PushDeviceRegistration.platform(String? Function() currentUid) =>
      PushDeviceRegistration(
        currentUid: currentUid,
        read: () async {
          final prefs = await SharedPreferences.getInstance();
          final value = prefs.getString('spark_push_installation_v1');
          return value == null
              ? null
              : Map<String, dynamic>.from(jsonDecode(value) as Map);
        },
        write: (value) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'spark_push_installation_v1',
            jsonEncode(value),
          );
        },
        send: (data) async {
          final client = AdminReportService.createClient();
          try {
            await client.pushDevice({
              ...data,
              if (AppEnvironment.sparkCommunicationsEnabled)
                'studyArea': AppEnvironment.area.id,
            });
          } finally {
            client.close();
          }
        },
      );
  Future<void> update({
    required String uid,
    String? token,
    required bool enabled,
  }) {
    final operation = _tail.catchError((Object _) {}).then((_) async {
      if (currentUid() != uid) return;
      final saved = await read();
      final installation =
          saved?['installation'] as String? ??
          base64UrlEncode(
            List<int>.generate(32, (_) => Random.secure().nextInt(256)),
          ).replaceAll('=', '');
      final sequence = (saved?['sequence'] as int? ?? 0) + 1;
      await write({'installation': installation, 'sequence': sequence});
      if (currentUid() != uid) return;
      await send({
        'installation': installation,
        'sequence': sequence,
        'mode': enabled ? 'register' : 'unregister',
        if (enabled) 'token': token,
      });
    });
    _tail = operation;
    return operation;
  }
}
