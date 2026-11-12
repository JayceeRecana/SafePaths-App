import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/models/broadcast_alert.dart';
import 'package:safepaths_app/screens/user/notifications_screen.dart';
import 'package:safepaths_app/services/sync_health.dart';
import 'package:safepaths_app/widgets/resident_alert_card.dart';
import 'map_home_controls_test.dart' as fixtures;

final start = DateTime(2026, 11, 8, 13, 30);
BroadcastAlert alert({
  DateTime? expires,
  bool withdrawn = false,
  String? reason,
  String severity = 'Warning',
  bool road = true,
}) => BroadcastAlert(
  id: 'resident-alert',
  title: 'Flood advisory for the selected road',
  message: 'Avoid the flooded section. Follow barangay instructions.',
  severity: severity,
  category: 'SYSTEM',
  createdAt: start,
  roadId: road ? 'road' : null,
  roadName: road ? 'Sample Road' : null,
  studyArea: AppEnvironment.area.id,
  expiresAt: expires ?? start.add(const Duration(hours: 3)),
  withdrawn: withdrawn,
  withdrawalReason: reason,
);
Widget card(
  BroadcastAlert a, {
  DateTime Function()? now,
  VoidCallback? onRoad,
  VoidCallback? onDismiss,
}) => fixtures.shell(
  Scaffold(
    body: SingleChildScrollView(
      child: ResidentAlertCard(
        alert: a,
        now: now ?? () => start,
        onViewRoad: onRoad,
        onDismiss: onDismiss,
      ),
    ),
  ),
);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'RESIDENT_ALERT_TEST=true');
  });
  testWidgets(
    'published severity, instructions, road and 12-hour expiry are visible',
    (tester) async {
      var opened = 0, hidden = 0;
      await tester.pumpWidget(
        card(alert(), onRoad: () => opened++, onDismiss: () => hidden++),
      );
      await tester.pumpAndSettle();
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('SYSTEM'), findsNothing);
      expect(find.text('Sample Road'), findsOneWidget);
      expect(find.textContaining('Active until:'), findsOneWidget);
      expect(find.textContaining('4:30 PM'), findsOneWidget);
      expect(find.text(alert().message), findsOneWidget);
      await tester.tap(find.text('View road'));
      expect(opened, 1);
      await tester.tap(find.byTooltip('Hide alert'));
      expect(hidden, 1);
    },
  );
  testWidgets(
    'detail expires without a new snapshot and withdrawal takes precedence',
    (tester) async {
      var clock = start;
      await tester.pumpWidget(
        card(
          alert(expires: start.add(const Duration(seconds: 2))),
          now: () => clock,
        ),
      );
      await tester.pump();
      clock = start.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Expired'), findsOneWidget);
      expect(find.textContaining('no longer active'), findsOneWidget);
      expect(find.textContaining('Active until:'), findsNothing);
      await tester.pumpWidget(
        card(alert(withdrawn: true, reason: 'Replaced by a newer advisory.')),
      );
      await tester.pump();
      expect(find.text('Withdrawn'), findsOneWidget);
      expect(
        find.textContaining('Replaced by a newer advisory.'),
        findsOneWidget,
      );
      expect(find.text('Expired'), findsNothing);
    },
  );
  testWidgets(
    'list removes expired alerts and does not label a cached empty list as clear',
    (tester) async {
      var clock = start;
      await tester.pumpWidget(
        fixtures.shell(
          NotificationsScreen(
            alerts: [alert(expires: start.add(const Duration(seconds: 2)))],
            syncCondition: SyncCondition.live,
            now: () => clock,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ResidentAlertCard), findsOneWidget);
      expect(find.text('LIVE UPDATES'), findsNothing);
      clock = start.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ResidentAlertCard), findsNothing);
      expect(find.text('No active alerts right now.'), findsOneWidget);
      await tester.pumpWidget(
        fixtures.shell(
          const NotificationsScreen(
            alerts: [],
            syncCondition: SyncCondition.cached,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('No active alerts right now.'), findsNothing);
      expect(find.textContaining('No saved information'), findsOneWidget);
    },
  );
  testWidgets('area-wide and missing metadata use honest labels', (
    tester,
  ) async {
    await tester.pumpWidget(card(alert(road: false)));
    await tester.pumpAndSettle();
    expect(
      find.text('Area-wide · ${AppEnvironment.area.name}'),
      findsOneWidget,
    );
    expect(find.text('View road'), findsNothing);
    final missing = BroadcastAlert.fromJson({
      'id': 'legacy',
      'title': 'Old notice',
      'message': 'Original text',
    });
    await tester.pumpWidget(card(missing));
    await tester.pump();
    expect(find.text('Issue time not recorded'), findsOneWidget);
    expect(find.text('End time not recorded'), findsOneWidget);
    expect(find.text('Alert area not recorded'), findsOneWidget);
    expect(find.text('Severity not recorded'), findsOneWidget);
    expect(find.textContaining('Active until:'), findsNothing);
  });
  testWidgets(
    'cards fit narrow screens with large text in both themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        for (final lang in ['en', 'fil']) {
          await tester.pumpWidget(
            fixtures.shell(
              Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ResidentAlertCard(
                      alert: alert(
                        withdrawn: true,
                        reason: 'A new announcement replaces this warning.',
                        severity: 'Critical',
                      ),
                      now: () => start,
                      onDismiss: () {},
                    ),
                  ),
                ),
              ),
              dark: dark,
              language: lang,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(OutlinedButton));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  test(
    'serialization preserves admin expiry, area and withdrawal metadata',
    () {
      final a = alert(withdrawn: true, reason: 'Updated instructions.');
      final b = BroadcastAlert.fromJson(a.toJson());
      expect(b.expiresAt, a.expiresAt);
      expect(b.studyArea, a.studyArea);
      expect(b.withdrawn, true);
      expect(b.withdrawalReason, a.withdrawalReason);
      expect(b.isActiveAt(start), false);
      expect(
        BroadcastAlert.fromJson({
          'createdAt': Timestamp.fromDate(start),
          'expiresAt': start.add(const Duration(hours: 1)).toIso8601String(),
        }).expiresAt,
        start.add(const Duration(hours: 1)),
      );
    },
  );
}
