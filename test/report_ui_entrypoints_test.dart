import 'package:safepaths_app/config/app_environment.dart';
import 'package:safepaths_app/screens/user/report_history_screen.dart';
import 'package:safepaths_app/services/report_history.dart';
import 'package:safepaths_app/l10n/app_strings.dart';
// Platform fakes keep notification routing tests local and exercise the actual
// Firebase-facing widgets, including ownership and live stream transitions.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as store;
import 'package:safepaths_app/models/user_report.dart';
import 'package:safepaths_app/screens/user/report_update_screen.dart';
import 'package:safepaths_app/widgets/report_details_bottom_sheet.dart';
import 'package:safepaths_app/widgets/report_message_thread.dart';
import 'package:safepaths_app/widgets/admin_reply_dialog.dart';
import 'package:safepaths_app/widgets/admin_dismiss_dialog.dart';
import 'package:safepaths_app/widgets/report_workflow_ui.dart';
import 'package:safepaths_app/services/admin_report_service.dart';
import 'package:safepaths_app/theme/app_theme.dart';

class TestAuth extends auth.FirebaseAuthPlatform {
  final events = StreamController<auth.UserPlatform?>.broadcast();
  auth.UserPlatform? user;
  @override
  auth.FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  auth.FirebaseAuthPlatform setInitialValues({
    auth.InternalUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  auth.UserPlatform? get currentUser => user;
  @override
  Stream<auth.UserPlatform?> userChanges() async* {
    yield user;
    yield* events.stream;
  }

  void signIn(String? uid, {bool verified = true}) {
    user = uid == null ? null : TestUser(this, uid, verified);
    events.add(user);
  }
}

class TestFactor extends auth.MultiFactorPlatform {
  TestFactor(super.auth);
}

class TestUser extends auth.UserPlatform {
  TestUser(TestAuth owner, String uid, bool verified)
    : super(
        owner,
        TestFactor(owner),
        auth.InternalUserDetails(
          userInfo: auth.InternalUserInfo(
            uid: uid,
            isAnonymous: false,
            isEmailVerified: verified,
          ),
          providerData: [],
        ),
      );
}

class TestStore extends store.FirebaseFirestorePlatform {
  final docs = <String, Map<String, dynamic>>{};
  final cached = <String>{};
  final events = <String, StreamController<store.DocumentSnapshotPlatform>>{};
  final messages = StreamController<store.QuerySnapshotPlatform>.broadcast();
  final messageQueries = <List<List<dynamic>>>[];
  @override
  store.FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;
  @override
  store.CollectionReferencePlatform collection(String path) =>
      TestCollection(this, path);
  @override
  store.DocumentReferencePlatform doc(String path) => TestDocument(this, path);
  store.DocumentSnapshotPlatform snapshot(String path) =>
      store.DocumentSnapshotPlatform(
        this,
        path,
        docs[path],
        store.InternalSnapshotMetadata(
          hasPendingWrites: false,
          isFromCache: cached.contains(path),
        ),
      );
  void update(
    String path,
    Map<String, dynamic> data, {
    bool fromCache = false,
  }) {
    docs[path] = data;
    if (fromCache) {
      cached.add(path);
    } else {
      cached.remove(path);
    }
    events[path]?.add(snapshot(path));
  }

  Stream<store.DocumentSnapshotPlatform> watch(String path) async* {
    final controller = events.putIfAbsent(
      path,
      () => StreamController.broadcast(),
    );
    yield snapshot(path);
    yield* controller.stream;
  }

  store.QuerySnapshotPlatform messagePage() => store.QuerySnapshotPlatform(
    [
      store.DocumentSnapshotPlatform(
        this,
        'report_messages/message',
        {
          'reportId': 'report',
          'userId': 'resident',
          'message': 'Current private update from the barangay.',
          'sender': 'SafePaths administrator',
          'createdAt': store.Timestamp.fromDate(DateTime(2026, 10, 30, 13)),
        },
        store.InternalSnapshotMetadata(
          hasPendingWrites: false,
          isFromCache: false,
        ),
      ),
    ],
    [],
    store.SnapshotMetadataPlatform(false, false),
  );
}

class TestDocument extends store.DocumentReferencePlatform {
  TestDocument(TestStore db, String path) : super(db, path);
  @override
  Stream<store.DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required store.ListenSource listenSource,
  }) => (firestore as TestStore).watch(path);
}

class TestCollection extends store.CollectionReferencePlatform {
  TestCollection(TestStore db, String path) : super(db, path);
  @override
  Map<String, dynamic> get parameters => {
    'where': <List<dynamic>>[],
    'orderBy': <List<dynamic>>[],
    'limit': null,
    'limitToLast': null,
    'startAt': null,
    'startAfter': null,
    'endAt': null,
    'endBefore': null,
  };
  @override
  store.DocumentReferencePlatform doc([String? id]) =>
      TestDocument(firestore as TestStore, '$path/$id');
  @override
  store.QueryPlatform where(List<List<dynamic>> conditions) =>
      TestQuery(firestore as TestStore, path, conditions);
}

class TestQuery extends store.QueryPlatform {
  final String collectionPath;
  final List<List<dynamic>> conditions, orders;
  TestQuery(
    TestStore db,
    this.collectionPath,
    this.conditions, [
    this.orders = const [],
    int? max,
  ]) : super(db, {
         'where': conditions,
         'orderBy': orders,
         'limit': max,
         'limitToLast': null,
         'startAt': null,
         'startAfter': null,
         'endAt': null,
         'endBefore': null,
       });
  @override
  store.QueryPlatform where(List<List<dynamic>> conditions) =>
      TestQuery(firestore as TestStore, collectionPath, conditions, orders);
  @override
  store.QueryPlatform orderBy(Iterable<List<dynamic>> orders) => TestQuery(
    firestore as TestStore,
    collectionPath,
    conditions,
    orders.toList(),
  );
  @override
  store.QueryPlatform limit(int limit) => TestQuery(
    firestore as TestStore,
    collectionPath,
    conditions,
    orders,
    limit,
  );
  @override
  Stream<store.QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required store.ListenSource listenSource,
  }) async* {
    final db = firestore as TestStore;
    db.messageQueries.add(conditions);
    yield db.messagePage();
    yield* db.messages.stream;
  }
}

Widget shell(
  Widget child, {
  bool dark = false,
  String language = 'en',
  double scale = 1,
}) => MaterialApp(
  key: ValueKey('$dark:$language:$scale'),
  theme: dark ? AppTheme.darkTheme : AppTheme.theme,
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);
Map<String, dynamic> record({String owner = 'resident', bool updates = true}) =>
    {
      'userId': owner,
      'title': 'Deep water: Unnamed residential (OSM 12345)',
      'description': 'Earlier resident observation.',
      'severity': 'High',
      'status': 'verified',
      'createdAt': DateTime(2026, 10, 30, 12).toIso8601String(),
      'observedAt': DateTime(2026, 10, 30, 12).toIso8601String(),
      'reviewedAt': DateTime(2026, 10, 30, 12, 30).toIso8601String(),
      'pointsAwarded': 10,
      'hasAdminUpdates': updates,
      'roadId': 'road',
      'incidentReviewStatus': 'not_passable',
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  late TestAuth identity;
  late TestStore database;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Firebase.initializeApp();
    identity = TestAuth();
    database = TestStore();
    auth.FirebaseAuthPlatform.instance = identity;
    store.FirebaseFirestorePlatform.instance = database;
  });
  setUp(() {
    identity.signIn('resident');
    database.docs.clear();
    database.cached.clear();
    database.messageQueries.clear();
    database.docs['reports/report'] = record();
    database.docs['roads/road'] = {
      'name': 'Unnamed residential',
      'status': 'passable',
      'isVerified': true,
      'updatedAt': DateTime(2026, 10, 30, 13).toIso8601String(),
    };
  });
  tearDownAll(() async {
    await identity.events.close();
    await database.messages.close();
    for (final e in database.events.values) {
      await e.close();
    }
  });
  testWidgets(
    'report notification opens the current timeline directly, shows road context, and remains owner scoped',
    (tester) async {
      await tester.pumpWidget(
        shell(const ReportUpdateScreen(reportId: 'report')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReportUpdatesPage), findsOneWidget);
      expect(find.text('See updates on your report'), findsNothing);
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('submission-preview-report')),
        findsOneWidget,
      );
      expect(
        database.messageQueries.single,
        contains(
          equals([
            store.FieldPath(['userId']),
            '==',
            'resident',
          ]),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Latest recorded road condition'),
        200,
      );
      expect(find.text('Latest recorded road condition'), findsOneWidget);
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Current private update from the barangay.'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Current private update from the barangay.'),
        findsOneWidget,
      );
      database.update('reports/report', record(owner: 'other'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportUpdatesPage), findsNothing);
      expect(
        find.text('Current private update from the barangay.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'notification retains cached warning and receives the first live admin message without reopening',
    (tester) async {
      database.docs['reports/report'] = record(updates: false);
      database.cached.add('reports/report');
      await tester.pumpWidget(
        shell(const ReportUpdateScreen(reportId: 'report')),
      );
      await tester.pumpAndSettle();
      expect(database.messageQueries, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Saved information; reconnect to check the latest update.'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      database.update('reports/report', record());
      await tester.pumpAndSettle();
      expect(database.messageQueries, isNotEmpty);
      await tester.scrollUntilVisible(
        find.text('Current private update from the barangay.'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      identity.signIn('other');
      await tester.pumpAndSettle();
      expect(
        find.text('Current private update from the barangay.'),
        findsNothing,
      );
      expect(find.byType(ReportUpdatesPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'notification blocks unavailable and unverified reports and recovers a private-stream failure',
    (tester) async {
      database.docs.remove('reports/report');
      await tester.pumpWidget(
        shell(const ReportUpdateScreen(reportId: 'report')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This report is unavailable. Check your report history.'),
        findsOneWidget,
      );
      expect(database.messageQueries, isEmpty);
      database.update('reports/report', record());
      identity.signIn('resident', verified: false);
      await tester.pumpAndSettle();
      expect(find.byType(ReportUpdatesPage), findsNothing);
      expect(database.messageQueries, isEmpty);
      identity.signIn('resident');
      await tester.pumpAndSettle();
      database.messages.addError(StateError('offline'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Retry updates'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Admin updates could not be loaded.'), findsOneWidget);
      await tester.tap(find.text('Retry updates'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Current private update from the barangay.'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Current private update from the barangay.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'community evidence stays read only and fits narrow large-text themes and languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: ReportDetailsBottomSheet(
                  report: UserReport.fromJson({...record(), 'id': 'report'}),
                ),
              ),
              dark: dark,
              language: language,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(ReportMessageThread), findsNothing);
          expect(find.byType(ReportUpdatesPage), findsNothing);
          expect(find.text('Admin Diagnostics'), findsNothing);
          expect(find.text('Reporter Profile'), findsNothing);
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'resident edit stays usable with large text and the keyboard and saves the same report',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      for (final language in ['en', 'fil']) {
        for (final dark in [false, true]) {
          String label(String key) =>
              language == 'fil' ? filipinoMessages[key] ?? key : key;
          UserReport? saved;
          String? note;
          final report = UserReport.fromJson({
            ...record(updates: false),
            'id': 'report',
            'status': 'pending',
            'pointsAwarded': null,
          });
          await tester.pumpWidget(
            shell(
              ReportHistoryScreen(
                currentAccount: () => 'resident',
                accountChanges: const Stream<String?>.empty(),
                createHistory: (_) =>
                    ReportHistory((_) async => ReportPage([report])),
                saveEdit: (item, level, description) async {
                  saved = item;
                  note = description;
                },
              ),
              language: language,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          final edit = find.text(label('Update Flood Level / Notes'));
          if (AppEnvironment.sparkFollowupsEnabled) {
            // Dated follow-ups replace the legacy in-place edit action, keeping
            // the original evidence intact. Their form is covered separately.
            expect(edit, findsNothing);
            expect(saved, isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            continue;
          }
          await tester.ensureVisible(edit);
          await tester.pumpAndSettle();
          await tester.tap(edit);
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 240);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextFormField),
            'Corrected details of the original observation.',
          );
          await tester.pump();
          final save = find.text(label('Save update'));
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(saved?.id, 'report');
          expect(note, 'Corrected details of the original observation.');
          expect(find.byType(ReportActionHeading), findsNothing);
          tester.view.resetViewInsets();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    },
  );
  testWidgets(
    'message action keeps its draft after failure and sends the current report reference only once',
    (tester) async {
      var calls = 0;
      Map<String, dynamic>? sent;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AdminReplyDialog(
                    reportId: 'report',
                    perform: (action, data) async {
                      calls++;
                      sent = data;
                      if (calls == 1) throw StateError('offline');
                      return const AdminActionResult(action: 'reply');
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportActionDialog), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Barangay staff are reviewing the evidence.',
      );
      await tester.pump();
      await tester.tap(find.text('Send update'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Barangay staff are reviewing the evidence.',
      );
      await tester.pump();
      await tester.tap(find.text('Send update'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(sent, {
        'reportId': 'report',
        'message': 'Barangay staff are reviewing the evidence.',
      });
      expect(find.byType(AdminReplyDialog), findsNothing);
    },
  );
  testWidgets(
    'decision forms preserve narrow layout and failed refresh cannot save old context',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loads = 0;
      var saves = 0;
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: AdminDismissDialog(
              reportId: 'report',
              loadContext: () async {
                loads++;
                if (loads > 1) throw StateError('offline');
                return {
                  'token': 'token',
                  'workflowVersion': 2,
                  'report': record(),
                };
              },
              perform: (action, data) async {
                saves++;
                throw StateError('uncertain save');
              },
            ),
          ),
          dark: true,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'This submission duplicates the earlier reviewed observation.',
      );
      await tester.pump();
      await tester.tap(find.text('Save dismissal'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      await tester.ensureVisible(find.text('Refresh latest report'));
      await tester.tap(find.text('Refresh latest report'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save dismissal'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'notification with an empty local cache waits for server confirmation instead of claiming deletion',
    (tester) async {
      database.docs.remove('reports/report');
      database.cached.add('reports/report');
      await tester.pumpWidget(
        shell(const ReportUpdateScreen(reportId: 'report')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Report not loaded yet'), findsOneWidget);
      expect(
        find.text('This report is unavailable. Check your report history.'),
        findsNothing,
      );
      expect(database.messageQueries, isEmpty);
      database.update('reports/report', record());
      await tester.pumpAndSettle();
      expect(find.text('Report not loaded yet'), findsNothing);
      expect(find.byType(ReportUpdatesPage), findsOneWidget);
      database.docs.remove('reports/report');
      database.events['reports/report']!.add(
        database.snapshot('reports/report'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReportUpdatesPage), findsNothing);
      expect(
        find.text('This report is unavailable. Check your report history.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
