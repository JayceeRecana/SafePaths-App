// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as store;
import 'package:safepaths_app/screens/user/road_details_screen.dart';
import 'package:safepaths_app/services/app_state_service.dart';
import 'package:safepaths_app/widgets/admin_review_dialog.dart';
import 'package:safepaths_app/theme/app_theme.dart';
import 'report_ui_entrypoints_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'ROAD_DETAILS_TEST=true');
    await Firebase.initializeApp();
    auth.FirebaseAuthPlatform.instance = fixtures.TestAuth()..signIn('admin');
    store.FirebaseFirestorePlatform.instance = fixtures.TestStore();
    AppStateService.instance.roads.add(
      RoadStatus(
        id: 'macarthur',
        name: 'MacArthur Highway',
        status: 'not_passable',
        notes: 'Checked flooding',
        updatedAt: DateTime.now(),
      ),
    );
  });
  testWidgets(
    'admin road details opens the checked editor directly for the selected road',
    (tester) async {
      SharedPreferences.setMockInitialValues({'user_role': 'UserRole.admin'});
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: const RoadDetailsScreen(roadId: 'macarthur'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final action = find.byKey(const ValueKey('road-report-action'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AdminReviewDialog), findsOneWidget);
      final editor = tester.widget<AdminReviewDialog>(
        find.byType(AdminReviewDialog),
      );
      expect(editor.roadIds, ['macarthur']);
      expect(editor.previewRoad!.id, 'macarthur');
      expect(editor.quickConditions, isTrue);
      expect(editor.showRoadSettings, isTrue);
      expect(editor.reportId, isNull);
      expect(editor.initialStatus, isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AdminReviewDialog), findsNothing);
      expect(find.byType(RoadDetailsScreen), findsOneWidget);
      await tester.tap(action);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AdminReviewDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
