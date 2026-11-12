import 'services/admin_report_service.dart';
import 'widgets/admin_review_dialog.dart';
import 'widgets/admin_reply_dialog.dart';
import 'widgets/admin_dismiss_dialog.dart';
import 'services/resident_report_update.dart';
import 'widgets/report_message_thread.dart';
import 'services/notification_service.dart';
import 'widgets/notification_status_card.dart';
import 'screens/user/report_update_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// Isolated reporting proof. The normal main.dart and environment defaults are unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/report_submission_coordinator.dart';
import 'services/spark_proof_client.dart';
import 'utils/report_image.dart';
import 'widgets/report_upload_progress.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = SparkProofConfiguration(
      firebaseProjectId: const String.fromEnvironment(
        'SPARK_PROOF_FIREBASE_PROJECT_ID',
      ),
      backendUrl: const String.fromEnvironment('SPARK_PROOF_BACKEND_URL'),
    );
    if (appFlavor != 'fieldtest') {
      throw StateError(
        'Use the separate fieldtest application for the Spark proof.',
      );
    }
    final app = await Firebase.initializeApp().timeout(
      const Duration(seconds: 8),
    );
    config.validate(
      flavor: appFlavor,
      actualProjectId: app.options.projectId,
      mainProjectId: DefaultFirebaseOptions.android.projectId,
    );
    if (NotificationService.testPushEnabled)
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    runApp(
      MaterialApp(
        title: 'SafePaths Spark Proof',
        home: SparkProofScreen(configuration: config),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Spark proof configuration is incomplete. Use the fieldtest flavor, a separate Firebase test project and the exact report-proof backend URL.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SparkProofScreen extends StatefulWidget {
  final SparkProofConfiguration configuration;
  const SparkProofScreen({super.key, required this.configuration});
  @override
  State<SparkProofScreen> createState() => _SparkProofScreenState();
}

class _SparkProofScreenState extends State<SparkProofScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _description = TextEditingController(
    text: 'Synthetic capstone test report. No real emergency.',
  );
  var _submission = ReportSubmissionCoordinator();
  late final SparkProofClient _client;
  Uint8List? _photo;
  String? _photoKey, _message;
  bool _busy = false, _admin = false;
  StreamSubscription<User?>? _account;
  String? _accountUid;
  int? _notificationTapOwner;

  @override
  void initState() {
    super.initState();
    if (NotificationService.testPushEnabled) {
      _bindPushTap();
      unawaited(
        NotificationService.instance.initialize().catchError((Object _) {}),
      );
    }
    _client = SparkProofClient(
      configuration: widget.configuration,
      token: () async {
        final user = FirebaseAuth.instance.currentUser;
        final token = await user?.getIdToken();
        if (FirebaseAuth.instance.currentUser?.uid != user?.uid) {
          throw const SparkProofException(
            'unauthenticated',
            'The test account changed. Sign in again.',
          );
        }
        return token;
      },
    );
    _account = FirebaseAuth.instance.userChanges().listen((user) {
      if (mounted && _accountUid != user?.uid) {
        setState(() {
          _accountUid = user?.uid;
          _photo = null;
          _photoKey = null;
          _admin = false;
          _message = null;
          _description.text =
              'Synthetic capstone test report. No real emergency.';
          _submission.dispose();
          _submission = ReportSubmissionCoordinator();
        });
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  void _bindPushTap() {
    _notificationTapOwner = NotificationService.instance.setOnNotificationTap((
      data,
    ) {
      final id = data?['reportId'];
      if (mounted &&
          id is String &&
          RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id))
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReportUpdateScreen(reportId: id)),
        );
    });
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy || _submission.isBusy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on SparkProofException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The test action failed. Check the connection and test configuration, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _action(() async {
    final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _email.text.trim(),
      password: _password.text,
    );
    _password.clear();
    final user = result.user;
    if (user == null || !user.emailVerified) {
      throw const SparkProofException(
        'unauthenticated',
        'Verify this test account email before reporting.',
      );
    }
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));
    if (mounted && FirebaseAuth.instance.currentUser?.uid == user.uid) {
      setState(() {
        if (NotificationService.testPushEnabled) _bindPushTap();
        _admin = profile.data()?['role'] == 'admin';
        _message = 'Signed in to the test project.';
      });
    }
  });

  Future<void> _pick() => _action(() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (image == null) return;
    if (await image.length() > maxReportPhotoBytes) {
      throw const SparkProofException(
        'too-large',
        'Choose a test image no larger than 10 MB.',
      );
    }
    final bytes = await image.readAsBytes();
    final prepared = await compute(prepareReportImage, bytes);
    if (mounted) {
      setState(() {
        _photo = prepared;
        _photoKey = DateTime.now().microsecondsSinceEpoch.toString();
      });
    }
  });

  Future<void> _send() => _action(() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) {
      throw const SparkProofException(
        'unauthenticated',
        'Sign in with a verified test account.',
      );
    }
    final text = _description.text.trim();
    if (text.isEmpty) {
      throw const SparkProofException(
        'invalid-argument',
        'Enter a synthetic test description.',
      );
    }
    final uid = user.uid, photo = _photo;
    await _submission.submit(
      photoKey: photo == null ? null : '$uid:$_photoKey',
      prepare: () async => photo!,
      upload: _client.upload,
      save: (reference) async {
        if (FirebaseAuth.instance.currentUser?.uid != uid) {
          throw const SparkProofException(
            'unauthenticated',
            'The test account changed. Sign in again.',
          );
        }
        final data = <String, dynamic>{
          'roadId': 'spark-proof-road',
          'title': 'Synthetic flood test',
          'description': text,
          'severity': 'High',
          'isEmergency': false,
          'location': {
            'lat': 14.676,
            'lng': 120.984,
            'source': 'manual',
            'imageUrl': ?reference,
          },
        };
        final prefs = await SharedPreferences.getInstance();
        final fingerprint = jsonEncode([
          widget.configuration.backend.toString(),
          uid,
          data,
        ]);
        const key = 'spark_proof_pending_report';
        Map<String, dynamic>? saved;
        try {
          saved =
              jsonDecode(prefs.getString(key) ?? '{}') as Map<String, dynamic>;
        } catch (_) {}
        final requestId = saved?['fingerprint'] == fingerprint
            ? saved!['id'] as String
            : base64UrlEncode(
                List.generate(24, (_) => Random.secure().nextInt(256)),
              ).replaceAll('=', '');
        await prefs.setString(
          key,
          jsonEncode({'fingerprint': fingerprint, 'id': requestId}),
        );
        final result = await _client.submit({...data, 'requestId': requestId});
        if (FirebaseAuth.instance.currentUser?.uid != uid) return;
        await prefs.remove(key);
        if (mounted) {
          setState(
            () => _message = result['replay'] == true
                ? 'Previously saved report confirmed; no duplicate created.'
                : 'Test report saved. Switch to the test admin account to review it.',
          );
        }
      },
    );
  });

  @override
  void dispose() {
    final tapOwner = _notificationTapOwner;
    if (tapOwner != null)
      NotificationService.instance.clearOnNotificationTap(tapOwner);
    unawaited(_account?.cancel());
    _client.close();
    _submission.dispose();
    _email.dispose();
    _password.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final locked = _busy || _submission.isBusy;
    return Scaffold(
      appBar: AppBar(title: const Text('SafePaths Spark Proof')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'TEST ONLY · Synthetic report/photo and admin-review flow. Map routing is not covered. Push requires the explicit test push option.',
            ),
            const SizedBox(height: 16),
            Text(
              'Firebase test project: ${widget.configuration.firebaseProjectId}',
            ),
            TextField(
              controller: _email,
              enabled: !locked,
              decoration: const InputDecoration(
                labelText: 'Test account email',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _password,
              enabled: !locked,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Test account password',
              ),
            ),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: locked ? null : _signIn,
                  child: const Text('Sign in / refresh account'),
                ),
                TextButton(
                  onPressed: locked || user == null
                      ? null
                      : () => _action(() async {
                          if (NotificationService.testPushEnabled)
                            await NotificationService.instance
                                .clearDeviceToken();
                          await FirebaseAuth.instance.signOut();
                        }),
                  child: const Text('Sign out'),
                ),
              ],
            ),
            if (user != null)
              Text(
                'Signed in: ${user.emailVerified ? 'verified' : 'unverified'} · ${_admin ? 'test admin' : 'resident'}',
              ),
            if (NotificationService.testPushEnabled)
              const NotificationStatusCard(reportUpdates: true),
            const Divider(),
            const Text(
              'Uses the seeded spark-proof-road and fixed test coordinates; these are not your GPS position.',
            ),
            TextField(
              controller: _description,
              enabled: !locked,
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Synthetic report description',
              ),
            ),
            if (_photo != null)
              Image.memory(_photo!, height: 140, fit: BoxFit.contain),
            TextButton(
              onPressed: locked || user == null ? null : _pick,
              child: const Text('Choose test photo'),
            ),
            FilledButton(
              onPressed:
                  locked ||
                      user == null ||
                      _submission.phase == ReportSubmissionPhase.complete
                  ? null
                  : _send,
              child: const Text('Submit / retry same report'),
            ),
            if (_submission.phase == ReportSubmissionPhase.complete)
              TextButton(
                onPressed: locked
                    ? null
                    : () => setState(() {
                        _submission.dispose();
                        _submission = ReportSubmissionCoordinator();
                        _photo = null;
                        _photoKey = null;
                        _message = null;
                      }),
                child: const Text('Start another synthetic test report'),
              ),
            AnimatedBuilder(
              animation: _submission,
              builder: (context, _) => ReportUploadProgress(
                phase: _submission.phase,
                progress: _submission.progress,
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_message!, semanticsLabel: _message),
              ),
            if (user != null)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('roads')
                    .doc('spark-proof-road')
                    .snapshots(includeMetadataChanges: true),
                builder: (context, snapshot) => Text(
                  snapshot.hasError
                      ? 'Current road condition could not be confirmed.'
                      : !snapshot.hasData
                      ? 'Checking current road condition...'
                      : 'Last recorded road condition: ${roadConditionLabel(snapshot.data!.data()?['status'] as String?)}${snapshot.data!.metadata.isFromCache ? ' (saved information)' : ''}',
                ),
              ),
            const Divider(),
            const Text(
              'Server-confirmed test reports (latest 20). A photo opens only after a fresh permission check.',
            ),
            if (user != null && user.emailVerified)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey('${user.uid}:$_admin'),
                stream:
                    (_admin
                            ? FirebaseFirestore.instance
                                  .collection('reports')
                                  .where(
                                    'roadId',
                                    isEqualTo: 'spark-proof-road',
                                  )
                            : FirebaseFirestore.instance
                                  .collection('reports')
                                  .where('userId', isEqualTo: user.uid))
                        .orderBy('createdAt', descending: true)
                        .limit(20)
                        .snapshots(includeMetadataChanges: true),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'Test history is unavailable. Check the test rules/indexes and connection.',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Text('Loading test history…');
                  }
                  final docs = snapshot.data!.docs;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (snapshot.data!.metadata.isFromCache)
                        const Text(
                          'Cached test history; server confirmation is pending.',
                        ),
                      if (docs.isEmpty) const Text('No test reports loaded.'),
                      for (final doc in docs)
                        Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                title: Text(
                                  doc.data()['title'] as String? ??
                                      'Test report',
                                ),
                                subtitle: Text(
                                  doc.data()['description'] as String? ?? '',
                                ),
                                trailing: doc.data()['imageUrl'] is String
                                    ? IconButton(
                                        tooltip: 'Open protected test photo',
                                        icon: const Icon(Icons.photo),
                                        onPressed: locked
                                            ? null
                                            : () => _action(() async {
                                                final uid = FirebaseAuth
                                                    .instance
                                                    .currentUser
                                                    ?.uid;
                                                final url = await _client
                                                    .photoUrl(
                                                      doc.data()['imageUrl']
                                                          as String,
                                                    );
                                                if (!context.mounted ||
                                                    FirebaseAuth
                                                            .instance
                                                            .currentUser
                                                            ?.uid !=
                                                        uid) {
                                                  return;
                                                }
                                                await showDialog<void>(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    title: const Text(
                                                      'Protected test photo',
                                                    ),
                                                    content: Image.network(
                                                      url,
                                                      errorBuilder: (_, _, _) =>
                                                          const Text(
                                                            'The photo link expired or could not load. Close and open it again.',
                                                          ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                            ),
                                                        child: const Text(
                                                          'Close',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                      )
                                    : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  'Report review: ${doc.data()['status']}',
                                ),
                              ),
                              if (doc.data()['incidentReviewStatus'] != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    'Road condition at review: ${roadConditionLabel(doc.data()['incidentReviewStatus'] as String?)}',
                                  ),
                                ),
                              if (doc.data()['pointsAwarded'] is num)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    'Trust change from this review: ${doc.data()['pointsAwarded']}',
                                  ),
                                ),
                              if (doc.data()['hasAdminUpdates'] == true)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: ReportMessageThread(
                                    reportId: doc.id,
                                    isAdmin: _admin,
                                  ),
                                ),
                              if (!_admin &&
                                  doc.data()['userId'] == user.uid &&
                                  [
                                    'pending',
                                    'under_review',
                                  ].contains(doc.data()['status']))
                                TextButton(
                                  onPressed: locked
                                      ? null
                                      : () => _action(() async {
                                          final saved = await showDialog<bool>(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (_) =>
                                                _ProofEditDialog(report: doc),
                                          );
                                          if (saved == true && mounted) {
                                            setState(
                                              () => _message =
                                                  'Resident edit confirmed by the server.',
                                            );
                                          }
                                        }),
                                  child: const Text(
                                    'Edit / retry report details',
                                  ),
                                ),
                              if (_admin)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (doc.data()['status'] == 'pending')
                                        OutlinedButton(
                                          onPressed: locked
                                              ? null
                                              : () => _action(() async {
                                                  final latest =
                                                      await AdminReportService.context(
                                                        reportId: doc.id,
                                                      );
                                                  final result =
                                                      await AdminReportService.perform(
                                                        'start',
                                                        {
                                                          'reportId': doc.id,
                                                          'contextToken':
                                                              latest['token'],
                                                        },
                                                      );
                                                  if (mounted)
                                                    setState(
                                                      () => _message =
                                                          result.confirmation,
                                                    );
                                                }),
                                          child: const Text('Start review'),
                                        ),
                                      if ([
                                        'pending',
                                        'under_review',
                                      ].contains(doc.data()['status']))
                                        FilledButton(
                                          onPressed: locked
                                              ? null
                                              : () => _action(() async {
                                                  final result =
                                                      await showAdminReview(
                                                        context,
                                                        reportId: doc.id,
                                                      );
                                                  if (result != null && mounted)
                                                    setState(
                                                      () => _message =
                                                          result.confirmation,
                                                    );
                                                }),
                                          child: const Text(
                                            'Review and verify',
                                          ),
                                        ),
                                      OutlinedButton(
                                        onPressed: locked
                                            ? null
                                            : () => _action(() async {
                                                final result =
                                                    await showAdminReply(
                                                      context,
                                                      doc.id,
                                                    );
                                                if (result != null && mounted)
                                                  setState(
                                                    () => _message =
                                                        result.confirmation,
                                                  );
                                              }),
                                        child: const Text('Message reporter'),
                                      ),
                                      if ([
                                        'pending',
                                        'under_review',
                                      ].contains(doc.data()['status']))
                                        TextButton(
                                          onPressed: locked
                                              ? null
                                              : () => _action(() async {
                                                  final result =
                                                      await showAdminDismiss(
                                                        context,
                                                        doc.id,
                                                      );
                                                  if (result != null &&
                                                      mounted) {
                                                    setState(
                                                      () => _message =
                                                          result.confirmation,
                                                    );
                                                  }
                                                }),
                                          child: const Text('Review dismissal'),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ProofEditDialog extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> report;
  const _ProofEditDialog({required this.report});
  @override
  State<_ProofEditDialog> createState() => _ProofEditDialogState();
}

class _ProofEditDialogState extends State<_ProofEditDialog> {
  late final _description = TextEditingController(
    text: widget.report.data()['description'] as String? ?? '',
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = widget.report.data();
      final version =
          (data['lastUpdatedByUser'] ?? data['createdAt']) as Timestamp;
      await ResidentReportUpdate.save(
        reportId: widget.report.id,
        severity: data['severity'] as String,
        description: _description.text,
        expectedUpdatedAt: version.toDate(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Save not confirmed. Your draft is kept. Wait for the report cooldown before retrying. If an admin has reviewed or changed it, close and reopen the latest report.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Edit synthetic report'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _description,
              enabled: !_saving,
              maxLength: 2000,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _description.text.trim().isEmpty ? null : _save,
          child: Text(_saving ? 'Confirming save...' : 'Save / retry edit'),
        ),
      ],
    ),
  );
}
