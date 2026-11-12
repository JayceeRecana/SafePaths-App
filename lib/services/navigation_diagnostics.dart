import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class NavigationDiagnostics extends ChangeNotifier {
  final DateTime Function() now;
  final List<Map<String, Object?>> _events = [];
  NavigationDiagnostics({DateTime Function()? now}) : now = now ?? DateTime.now;
  static const allowedFields = {
    'accuracyMeters',
    'fixAgeSeconds',
    'gpsOutcome',
    'fixSource',
    'distanceToRouteMeters',
    'ignoredLowAccuracy',
    'shouldReroute',
    'roadIds',
    'reason',
    'outcome',
    'routeCount',
    'cooldownMs',
    'errorType',
    'mode',
  };
  final Map<String, Object?> latest = {};

  void record(String event, [Map<String, Object?> fields = const {}]) {
    final safe = Map<String, Object?>.fromEntries(
      fields.entries.where((e) => allowedFields.contains(e.key)),
    );
    latest.addAll(safe);
    latest['lastEvent'] = event;
    latest['lastEventAt'] = now().toUtc().toIso8601String();
    if (event == 'roads_received')
      latest['roadUpdateAt'] = latest['lastEventAt'];
    if (event == 'request_started')
      latest['requestStartedAt'] = latest['lastEventAt'];
    if (event == 'request_finished')
      latest['requestFinishedAt'] = latest['lastEventAt'];
    _events.add({'at': latest['lastEventAt'], 'event': event, ...safe});
    if (_events.length > 2000) _events.removeAt(0);
    notifyListeners();
  }

  String exportJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'format': 'safepaths-navigation-test-v1', 'events': _events});

  Future<String> save() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/navigation-test-${now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(exportJson());
    return file.path;
  }
}
