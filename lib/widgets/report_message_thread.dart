import 'admin_report_messages.dart';
import 'resident_report_details.dart';
import 'resident_report_status.dart';
import '../utils/report_freshness.dart';
import '../services/admin_road_overview.dart';
import '../services/weather_service.dart';
import 'report_workflow_ui.dart';
import '../models/road_status.dart';
import 'report_review_summary.dart';
import 'report_followup_link.dart';
import '../screens/user/report_clarification_screen.dart';
import 'safe_image.dart';
import '../services/report_history.dart' show retainDisplacedHead;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/user_report.dart';
import '../theme/app_palette.dart';
import 'app_top_bar.dart';
import 'report_submission_preview.dart';

/// A launcher rather than a thread that expands inside every report card.
class ReportMessageThread extends StatelessWidget {
  final String reportId;
  final UserReport? report;
  final bool isAdmin, feedback, hasServerUpdates;
  final List<ReportReply> legacyReplies;
  final WidgetBuilder? pageBuilder;
  const ReportMessageThread({
    super.key,
    required this.reportId,
    this.report,
    this.isAdmin = false,
    this.feedback = false,
    this.hasServerUpdates = true,
    this.legacyReplies = const [],
    this.pageBuilder,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder:
                pageBuilder ??
                (_) => ReportUpdatesPage(
                  reportId: reportId,
                  report: report,
                  isAdmin: isAdmin,
                  feedback: feedback,
                  hasServerUpdates: hasServerUpdates,
                  legacyReplies: legacyReplies,
                ),
          ),
        ),
        icon: const Icon(Icons.forum_outlined, size: 16),
        label: Text(
          tr(
            context,
            report != null && !feedback
                ? (isAdmin ? 'Report updates' : 'See updates on your report')
                : 'View private admin updates',
          ),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.of(context).primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          side: BorderSide(
            color: AppPalette.of(context).primary.withValues(alpha: .3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
  );
}

Widget _clarificationButton(
  BuildContext context,
  UserReport report,
  bool isAdmin,
) => Padding(
  padding: const EdgeInsets.only(top: 10),
  child: OutlinedButton.icon(
    key: const ValueKey('report-question-action'),
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportClarificationScreen(
          reportId: report.id,
          report: report,
          isAdmin: isAdmin,
        ),
      ),
    ),
    icon: const Icon(Icons.question_answer_outlined, size: 20),
    label: Text(
      tr(
        context,
        report.awaitsResident && !isAdmin
            ? 'Reply to question'
            : 'View question and reply',
      ),
      textAlign: TextAlign.center,
    ),
  ),
);

class _ReportNextAction extends StatelessWidget {
  final UserReport report;
  final bool isAdmin;
  const _ReportNextAction({required this.report, required this.isAdmin});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final waiting = report.awaitsResident;
    final answered = report.clarificationRepliedAt != null && !waiting;
    final title = waiting
        ? (isAdmin ? 'Waiting for the resident' : 'Your reply is needed')
        : answered
        ? (isAdmin ? 'Resident reply received' : 'Reply received by SafePaths')
        : report.status == 'under_review'
        ? 'Under barangay review'
        : (isAdmin ? 'Needs review' : 'Waiting for barangay review');
    final detail = waiting
        ? (isAdmin
              ? 'The resident can answer the clarification question on this report.'
              : 'Read the barangay question and reply when you can do so safely.')
        : answered
        ? (isAdmin
              ? 'Read the question and reply before recording your review decision.'
              : 'Your report is back in the barangay review queue.')
        : (isAdmin
              ? 'Review the submitted evidence before recording a decision.'
              : 'You can reply when the barangay asks a clarification question.');
    final color = waiting ? p.onWarningContainer : p.primary;
    return ReportPanel(
      tint: waiting ? p.warningContainer : p.primary.withValues(alpha: .06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                waiting
                    ? Icons.question_answer_outlined
                    : Icons.fact_check_outlined,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr(context, title),
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tr(context, detail),
                      style: TextStyle(
                        color: p.onSurface,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (report.clarificationRequestId != null)
            _clarificationButton(context, report, isAdmin),
        ],
      ),
    );
  }
}

class AdminUpdateMessage {
  final String id, message, sender;
  final DateTime? createdAt, photoObservedAt;
  final String? imageUrl;
  const AdminUpdateMessage({
    required this.id,
    required this.message,
    required this.sender,
    this.createdAt,
    this.photoObservedAt,
    this.imageUrl,
  });
}

/// Lazy rendering keeps long message histories off the report-list screen.
class AdminUpdatesContent extends StatelessWidget {
  final List<AdminUpdateMessage> messages;
  final RoadStatus? road;
  final bool showReviewSummary, isAdmin;
  final UserReport? report;
  final bool fromCache, loadingOlder, hasMore, loading;
  final String? error;
  final VoidCallback? onLoadOlder, onRetry;
  const AdminUpdatesContent({
    super.key,
    required this.messages,
    this.road,
    this.showReviewSummary = false,
    this.isAdmin = false,
    this.report,
    this.fromCache = false,
    this.loading = false,
    this.onRetry,
    this.loadingOlder = false,
    this.hasMore = false,
    this.error,
    this.onLoadOlder,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: messages.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (report != null) ...[
                  ReportSubmissionPreview(report: report!, road: road),
                  if (report!.reviewOpen) ...[
                    const SizedBox(height: 12),
                    _ReportNextAction(report: report!, isAdmin: isAdmin),
                  ],
                  if (!report!.reviewOpen) ...[
                    const SizedBox(height: 12),
                    ReportReviewSummary(
                      report: report!,
                      road: road,
                      compact: true,
                    ),
                  ],
                  if (showReviewSummary) ReportFollowupLink(report: report!),
                  if (!report!.reviewOpen &&
                      report!.clarificationRequestId != null)
                    _clarificationButton(context, report!, isAdmin),
                  const SizedBox(height: 16),
                ],
                if (report != null)
                  const ReportUpdatesHeader()
                else
                  Text(
                    tr(context, 'Private admin updates. Newest first.'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                if (fromCache) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      context,
                      'Saved information; reconnect to check the latest update.',
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
                if (loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (messages.isEmpty && !loading && error == null) ...[
                  const SizedBox(height: 16),
                  Text(
                    tr(
                      context,
                      fromCache
                          ? 'No saved admin updates are available on this device.'
                          : 'No admin messages are recorded yet.',
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        if (index == messages.length + 1) {
          return Column(
            children: [
              if (error != null)
                Text(
                  tr(context, error!),
                  style: GoogleFonts.inter(fontSize: 12, color: palette.error),
                ),
              if (error != null && onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(tr(context, 'Retry updates')),
                ),
              if (hasMore)
                TextButton(
                  onPressed: loadingOlder ? null : onLoadOlder,
                  child: Text(
                    tr(
                      context,
                      loadingOlder ? 'Loading...' : 'Load older updates',
                    ),
                  ),
                ),
            ],
          );
        }
        final item = messages[index - 1];
        if (report != null) {
          return ReportUpdateTimelineEntry(
            key: ValueKey(item.id),
            message: item,
            first: index == 1,
            last: index == messages.length,
          );
        }
        return Container(
          key: ValueKey(item.id),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: palette.outlineVariant.withValues(alpha: .3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.sender,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.createdAt == null
                    ? tr(context, 'Confirming time...')
                    : localizedDateTime(context, item.createdAt!),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// History and admin launchers subscribe to the current report, not their card snapshot.
/// Notification entry already supplies live report/road streams and can reuse them.
class ReportUpdatesPage extends StatefulWidget {
  final RoadStatus? road;
  final bool initialMessages, embeddedAdmin;
  final bool showReviewSummary, reportFromCache, reportIsLive;
  final String reportId;
  final UserReport? report;
  final bool isAdmin, feedback, hasServerUpdates;
  final List<ReportReply> legacyReplies;
  const ReportUpdatesPage({
    super.key,
    this.initialMessages = true,
    this.embeddedAdmin = false,
    this.road,
    this.showReviewSummary = false,
    this.reportFromCache = false,
    this.reportIsLive = false,
    required this.reportId,
    this.report,
    this.isAdmin = false,
    this.feedback = false,
    this.hasServerUpdates = true,
    this.legacyReplies = const [],
  });
  @override
  State<ReportUpdatesPage> createState() => _LiveReportUpdatesState();
}

class _LiveReportUpdatesState extends State<ReportUpdatesPage> {
  late final String? _openingUid;
  int _retry = 0;
  @override
  void initState() {
    super.initState();
    _openingUid = FirebaseAuth.instance.currentUser?.uid;
  }

  Widget _messages(
    UserReport? report,
    RoadStatus? road,
    bool cached, {
    bool? hasServerUpdates,
    List<ReportReply>? legacy,
  }) => _ReportUpdatesMessagesPage(
    key: ValueKey(
      '${FirebaseAuth.instance.currentUser?.uid}:${widget.reportId}',
    ),
    reportId: widget.reportId,
    initialMessages: widget.initialMessages,
    embeddedAdmin: widget.embeddedAdmin,
    report: report,
    road: road,
    showReviewSummary: widget.showReviewSummary,
    reportFromCache: cached,
    isAdmin: widget.isAdmin,
    feedback: widget.feedback,
    hasServerUpdates: hasServerUpdates ?? widget.hasServerUpdates,
    legacyReplies: legacy ?? widget.legacyReplies,
  );

  Widget _waiting(BuildContext context, String? message) => Scaffold(
    backgroundColor: AppPalette.of(context).surface,
    appBar: AppTopBar(
      title: tr(
        context,
        widget.isAdmin ? 'Report updates' : 'Updates on your report',
      ),
      showBackButton: true,
      showProfile: false,
      showSettingsAction: false,
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: message == null
            ? const CircularProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr(context, message), textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => setState(() => _retry++),
                      child: Text(tr(context, 'Retry updates')),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser?.uid != _openingUid) {
      return _waiting(
        context,
        'Account changed. Reopen updates from your own reports.',
      );
    }
    if (widget.feedback || widget.report == null || widget.reportIsLive) {
      return _messages(widget.report, widget.road, widget.reportFromCache);
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, auth) {
        final user = auth.data;
        if (user == null ||
            user.uid != _openingUid ||
            !user.emailVerified ||
            user.isAnonymous ||
            widget.report!.id != widget.reportId ||
            (!widget.isAdmin && widget.report!.userId != user.uid)) {
          return _waiting(
            context,
            'Account changed. Reopen updates from your own reports.',
          );
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey('live-report:${user.uid}:${widget.reportId}:$_retry'),
          stream: FirebaseFirestore.instance
              .collection('reports')
              .doc(widget.reportId)
              .snapshots(includeMetadataChanges: true),
          builder: (context, snapshot) {
            if (snapshot.hasError ||
                (snapshot.hasData && !snapshot.data!.exists)) {
              return _waiting(
                context,
                'This report could not be refreshed. Check your connection and retry.',
              );
            }
            if (!snapshot.hasData) return _waiting(context, null);
            UserReport current;
            try {
              current = UserReport.fromJson({
                ...snapshot.data!.data()!,
                'id': widget.reportId,
              });
            } catch (_) {
              return _waiting(
                context,
                'This report could not be refreshed. Check your connection and retry.',
              );
            }
            if (FirebaseAuth.instance.currentUser?.uid != user.uid ||
                (!widget.isAdmin && current.userId != user.uid)) {
              return _waiting(
                context,
                'Account changed. Reopen updates from your own reports.',
              );
            }
            final legacy = current.adminReplies.isNotEmpty
                ? current.adminReplies
                : [
                    if (current.adminReply?.trim().isNotEmpty == true)
                      ReportReply(
                        message: current.adminReply!,
                        timestamp: current.reviewedAt ?? current.createdAt,
                      ),
                  ];
            Widget content(RoadStatus? road, bool roadCached) => _messages(
              current,
              road,
              snapshot.data!.metadata.isFromCache || roadCached,
              // Watch even an empty or legacy-only thread for its first server message.
              hasServerUpdates: true,
              legacy: legacy,
            );
            if (current.roadId == null) return content(null, false);
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              key: ValueKey('live-road:${user.uid}:${current.roadId}'),
              stream: FirebaseFirestore.instance
                  .collection('roads')
                  .doc(current.roadId)
                  .snapshots(includeMetadataChanges: true),
              builder: (context, roadSnapshot) {
                RoadStatus? road;
                if (!roadSnapshot.hasError &&
                    roadSnapshot.hasData &&
                    roadSnapshot.data!.exists) {
                  try {
                    road = RoadStatus.fromJson({
                      ...roadSnapshot.data!.data()!,
                      'id': current.roadId,
                    });
                  } catch (_) {}
                }
                return content(
                  road,
                  roadSnapshot.data?.metadata.isFromCache ?? false,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ReportUpdatesMessagesPage extends StatefulWidget {
  final RoadStatus? road;
  final bool initialMessages, embeddedAdmin;
  final bool showReviewSummary, reportFromCache;
  final String reportId;
  final UserReport? report;
  final bool isAdmin, feedback, hasServerUpdates;
  final List<ReportReply> legacyReplies;
  const _ReportUpdatesMessagesPage({
    super.key,
    this.initialMessages = true,
    this.embeddedAdmin = false,
    this.road,
    this.showReviewSummary = false,
    this.reportFromCache = false,
    required this.reportId,
    this.report,
    this.isAdmin = false,
    this.feedback = false,
    this.hasServerUpdates = true,
    this.legacyReplies = const [],
  });
  @override
  State<_ReportUpdatesMessagesPage> createState() =>
      __ReportUpdatesMessagesPageState();
}

class __ReportUpdatesMessagesPageState
    extends State<_ReportUpdatesMessagesPage> {
  StreamSubscription<User?>? _auth;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  Query<Map<String, dynamic>>? _query;
  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> _older = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _previousHead = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _uid, _error;
  int _generation = 0;
  bool _accountChanged = false, _loadingOlder = false, _hasMore = true;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _auth = FirebaseAuth.instance.userChanges().listen((user) {
      if (user?.uid != _uid && mounted) {
        setState(() {
          _generation++;
          _accountChanged = true;
          _stream = null;
          _query = null;
          _older.clear();
          _previousHead = [];
          _cursor = null;
        });
      } else if (mounted) {
        setState(() {});
      }
    });
    if (widget.hasServerUpdates) _load();
  }

  @override
  void didUpdateWidget(covariant _ReportUpdatesMessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportId != widget.reportId ||
        oldWidget.feedback != widget.feedback ||
        oldWidget.isAdmin != widget.isAdmin ||
        oldWidget.hasServerUpdates != widget.hasServerUpdates) {
      if (widget.hasServerUpdates) {
        _load();
      } else {
        _generation++;
        _stream = null;
        _query = null;
        _older.clear();
        _previousHead = [];
        _cursor = null;
        _loadingOlder = false;
        _error = null;
        _hasMore = true;
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_auth?.cancel());
    super.dispose();
  }

  void _load() {
    if (_uid == null ||
        _accountChanged ||
        FirebaseAuth.instance.currentUser?.uid != _uid) {
      return;
    }
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(widget.feedback ? 'feedback_messages' : 'report_messages')
        .where(
          widget.feedback ? 'feedbackId' : 'reportId',
          isEqualTo: widget.reportId,
        );
    if (!widget.isAdmin) query = query.where('userId', isEqualTo: _uid);
    query = query
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    setState(() {
      _generation++;
      _loadingOlder = false;
      _query = query;
      _stream = query.limit(20).snapshots(includeMetadataChanges: true);
      _older.clear();
      _previousHead = [];
      _cursor = null;
      _error = null;
      _hasMore = true;
    });
  }

  Future<void> _more() async {
    final cursor = _cursor, query = _query, uid = _uid;
    final generation = _generation;
    bool current() =>
        mounted &&
        !_accountChanged &&
        generation == _generation &&
        FirebaseAuth.instance.currentUser?.uid == uid;
    if (cursor == null || query == null || _loadingOlder || !current()) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await query
          .startAfterDocument(cursor)
          .limit(20)
          .get(const GetOptions(source: Source.server));
      if (!current()) return;
      setState(() {
        for (final doc in page.docs) {
          _older[doc.id] = doc;
        }
        if (page.docs.isNotEmpty) _cursor = page.docs.last;
        _hasMore = page.docs.length == 20;
        _error = null;
      });
    } catch (_) {
      if (current()) {
        setState(() => _error = 'Older updates could not be loaded. Retry.');
      }
    } finally {
      if (current()) setState(() => _loadingOlder = false);
    }
  }

  List<AdminUpdateMessage> _messages(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = [
      for (final doc in docs)
        AdminUpdateMessage(
          id: doc.id,
          message: '${doc.data()['message'] ?? ''}',
          sender: '${doc.data()['sender'] ?? 'SafePaths administrator'}',
          imageUrl: doc.data()['imageUrl'] as String?,
          photoObservedAt: (doc.data()['photoObservedAt'] as Timestamp?)
              ?.toDate(),
          createdAt: (doc.data()['createdAt'] as Timestamp?)?.toDate(),
        ),
      for (var index = 0; index < widget.legacyReplies.length; index++)
        AdminUpdateMessage(
          id: 'legacy-$index',
          message: widget.legacyReplies[index].message,
          sender: widget.legacyReplies[index].sender,
          createdAt: widget.legacyReplies[index].timestamp,
        ),
    ];
    items.sort((a, b) {
      final time = (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
        a.createdAt?.millisecondsSinceEpoch ?? 0,
      );
      return time == 0 ? b.id.compareTo(a.id) : time;
    });
    return items;
  }

  bool get _reportMismatch =>
      widget.report != null &&
      (widget.report!.id != widget.reportId ||
          (!widget.isAdmin && widget.report!.userId != _uid));

  UserReport? get _visibleReport {
    final report = widget.report;
    if (report == null ||
        report.id != widget.reportId ||
        _accountChanged ||
        FirebaseAuth.instance.currentUser?.uid != _uid ||
        FirebaseAuth.instance.currentUser?.emailVerified != true ||
        FirebaseAuth.instance.currentUser?.isAnonymous == true ||
        (!widget.isAdmin && report.userId != _uid))
      return null;
    return report;
  }

  Widget _updatesContent({
    required List<AdminUpdateMessage> messages,
    UserReport? report,
    RoadStatus? road,
    bool isAdmin = false,
    bool fromCache = false,
    bool loading = false,
    bool loadingOlder = false,
    bool hasMore = false,
    bool showReviewSummary = false,
    String? error,
    VoidCallback? onRetry,
    VoidCallback? onLoadOlder,
  }) {
    if (isAdmin && widget.embeddedAdmin && report != null) {
      return AdminReportMessages(
        report: report,
        messages: messages,
        fromCache: fromCache,
        loading: loading,
        loadingOlder: loadingOlder,
        hasMore: hasMore,
        error: error,
        onRetry: onRetry,
        onLoadOlder: onLoadOlder,
      );
    }
    if (!isAdmin && !widget.feedback && report != null) {
      return ResidentReportUpdatesContent(
        report: report,
        road: road,
        messages: messages,
        initialMessages: widget.initialMessages,
        fromCache: fromCache,
        loading: loading,
        loadingOlder: loadingOlder,
        hasMore: hasMore,
        error: error,
        onRetry: onRetry,
        onLoadOlder: onLoadOlder,
      );
    }
    return AdminUpdatesContent(
      messages: messages,
      report: report,
      road: road,
      isAdmin: isAdmin,
      fromCache: fromCache,
      loading: loading,
      loadingOlder: loadingOlder,
      hasMore: hasMore,
      showReviewSummary: showReviewSummary,
      error: error,
      onRetry: onRetry,
      onLoadOlder: onLoadOlder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page(context);
    return widget.embeddedAdmin ? page.body! : page;
  }

  Scaffold _page(BuildContext context) => Scaffold(
    appBar: !widget.isAdmin && !widget.feedback && _visibleReport != null
        ? ResidentReportUpdatesHeader(
            report: _visibleReport!,
            road: widget.road,
            scale: MediaQuery.textScalerOf(context).scale(1),
          )
        : AppTopBar(
            title: tr(
              context,
              widget.feedback || widget.report == null
                  ? 'Admin updates'
                  : widget.isAdmin
                  ? 'Report updates'
                  : 'Updates on your report',
            ),
            showBackButton: true,
            showProfile: false,
            showSettingsAction: false,
          ),
    body: SafeArea(
      child:
          _accountChanged ||
              _reportMismatch ||
              _uid == null ||
              FirebaseAuth.instance.currentUser?.emailVerified != true ||
              FirebaseAuth.instance.currentUser?.isAnonymous == true ||
              FirebaseAuth.instance.currentUser?.uid != _uid
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  tr(
                    context,
                    'Account changed. Reopen updates from your own reports.',
                  ),
                ),
              ),
            )
          : !widget.hasServerUpdates
          ? _updatesContent(
              messages: _messages([]),
              report: _visibleReport,
              isAdmin: widget.isAdmin,
              fromCache: widget.reportFromCache,
              road: widget.road,
              showReviewSummary: widget.showReviewSummary,
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _updatesContent(
                    messages: _messages([]),
                    report: _visibleReport,
                    isAdmin: widget.isAdmin,
                    fromCache: widget.reportFromCache,
                    road: widget.road,
                    showReviewSummary: widget.showReviewSummary,
                    error: 'Admin updates could not be loaded.',
                    onRetry: _load,
                  );
                }
                if (!snapshot.hasData) {
                  return _updatesContent(
                    messages: _messages([]),
                    report: _visibleReport,
                    isAdmin: widget.isAdmin,
                    fromCache: widget.reportFromCache,
                    road: widget.road,
                    showReviewSummary: widget.showReviewSummary,
                    loading: true,
                  );
                }
                if (_accountChanged ||
                    FirebaseAuth.instance.currentUser?.uid != _uid) {
                  return const SizedBox.shrink();
                }
                final latest = snapshot.data!.docs;
                if (_older.isEmpty && !_loadingOlder && latest.isNotEmpty) {
                  _cursor = latest.last;
                }
                retainDisplacedHead(
                  older: _older,
                  previous: _previousHead,
                  latest: latest,
                  loadingOlder: _loadingOlder,
                  id: (doc) => doc.id,
                );
                _previousHead = latest;
                final all = {
                  ..._older,
                  for (final doc in latest) doc.id: doc,
                }.values.toList();
                return _updatesContent(
                  messages: _messages(all),
                  report: _visibleReport,
                  isAdmin: widget.isAdmin,
                  road: widget.road,
                  showReviewSummary: widget.showReviewSummary,
                  fromCache:
                      widget.reportFromCache ||
                      snapshot.data!.metadata.isFromCache,
                  loadingOlder: _loadingOlder,
                  hasMore:
                      _hasMore && (_older.isNotEmpty || latest.length == 20),
                  error: _error,
                  onLoadOlder: _more,
                );
              },
            ),
    ),
  );
}

class ResidentReportUpdatesHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final UserReport report;
  final RoadStatus? road;
  final double scale;
  const ResidentReportUpdatesHeader({
    super.key,
    required this.report,
    this.road,
    this.scale = 1,
  });
  @override
  Size get preferredSize => Size.fromHeight(scale > 1.3 ? 200 : 100);
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final name = reportRoadName(report, road: road);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name == 'Unnamed residential road' ? tr(context, name) : name,
          maxLines: scale > 1.3 ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(
            fontSize: 17,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: p.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${tr(context, 'Reported')}: ${localizedDateTime(context, report.createdAt)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: p.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Material(
      color: p.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BackButton(color: p.onSurface),
              const SizedBox(width: 2),
              Expanded(
                child: scale > 1.3
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          details,
                          const SizedBox(height: 8),
                          ResidentReportStatusBadge(report: report),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: details),
                          const SizedBox(width: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: ResidentReportStatusBadge(report: report),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resident-only presentation; the authenticated parent owns all live streams.
/// Report evidence and road decisions stay outside the private-message list.
class ResidentReportUpdatesContent extends StatefulWidget {
  final UserReport report;
  final RoadStatus? road;
  final List<AdminUpdateMessage> messages;
  final bool initialMessages, fromCache, loading, loadingOlder, hasMore;
  final String? error;
  final VoidCallback? onRetry, onLoadOlder;
  const ResidentReportUpdatesContent({
    super.key,
    required this.report,
    this.road,
    required this.messages,
    this.initialMessages = true,
    this.fromCache = false,
    this.loading = false,
    this.loadingOlder = false,
    this.hasMore = false,
    this.error,
    this.onRetry,
    this.onLoadOlder,
  });
  @override
  State<ResidentReportUpdatesContent> createState() =>
      _ResidentReportUpdatesContentState();
}

class _ResidentReportUpdatesContentState
    extends State<ResidentReportUpdatesContent> {
  late bool _messages;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _messages = widget.initialMessages;
    _latest();
  }

  void _latest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _messages && _scroll.hasClients)
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String? latestId(List<AdminUpdateMessage> messages) {
    if (messages.isEmpty) return null;
    final sorted = [...messages]
      ..sort(
        (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.createdAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    return sorted.first.id;
  }

  @override
  void didUpdateWidget(covariant ResidentReportUpdatesContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id) {
      _messages = widget.initialMessages;
      _latest();
    } else if (latestId(oldWidget.messages) != latestId(widget.messages) &&
        (!_scroll.hasClients || _scroll.position.extentAfter < 100))
      _latest();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), report = widget.report;
    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        tr(context, text),
        style: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: p.onSurface,
        ),
      ),
    );
    final sorted = [...widget.messages]
      ..sort((a, b) {
        final n = (a.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
          b.createdAt?.millisecondsSinceEpoch ?? 0,
        );
        return n == 0 ? a.id.compareTo(b.id) : n;
      });
    Widget notices() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.fromCache)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              tr(
                context,
                'Saved information; reconnect to check the latest update.',
              ),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: p.onWarningContainer,
              ),
            ),
          ),
        if (widget.loading) const LinearProgressIndicator(),
        if (widget.error != null) ...[
          Text(
            tr(context, widget.error!),
            style: TextStyle(color: p.error, fontSize: 12),
          ),
          if (widget.onRetry != null)
            TextButton(
              onPressed: widget.onRetry,
              child: Text(tr(context, 'Retry updates')),
            ),
        ],
      ],
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: p.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                for (final messages in [false, true])
                  Expanded(
                    child: Semantics(
                      selected: _messages == messages,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() => _messages = messages);
                          if (messages) _latest();
                        },
                        icon: Icon(
                          messages
                              ? Icons.forum_outlined
                              : Icons.description_outlined,
                          size: 16,
                        ),
                        label: Text(
                          tr(context, messages ? 'Messages' : 'Report'),
                          textAlign: TextAlign.center,
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 44),
                          backgroundColor: _messages == messages
                              ? p.surfaceContainerLowest
                              : Colors.transparent,
                          foregroundColor: _messages == messages
                              ? p.primary
                              : p.onSurfaceVariant,
                          textStyle: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _messages
              ? ListView(
                  key: ValueKey('resident-messages-${report.id}'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    Text(
                      tr(context, 'Private messages about your report'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: p.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (report.reviewOpen &&
                        !report.awaitsResident &&
                        report.clarificationRepliedAt == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          tr(
                            context,
                            report.status == 'under_review'
                                ? 'Under barangay review'
                                : 'Waiting for barangay review',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ),
                    notices(),
                    if (widget.hasMore)
                      Center(
                        child: TextButton(
                          onPressed: widget.loadingOlder
                              ? null
                              : widget.onLoadOlder,
                          child: Text(
                            tr(
                              context,
                              widget.loadingOlder
                                  ? 'Loading...'
                                  : 'Load older updates',
                            ),
                          ),
                        ),
                      ),
                    if (sorted.isEmpty &&
                        !widget.loading &&
                        widget.error == null)
                      ReportPanel(
                        child: Text(
                          tr(
                            context,
                            widget.fromCache
                                ? 'No saved admin updates are available on this device.'
                                : 'No admin messages are recorded yet.',
                          ),
                          style: TextStyle(
                            color: p.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    for (var index = 0; index < sorted.length; index++) ...[
                      if (sorted[index].createdAt != null &&
                          (index == 0 ||
                              sorted[index - 1].createdAt == null ||
                              DateUtils.dateOnly(
                                    sorted[index].createdAt!.toLocal(),
                                  ) !=
                                  DateUtils.dateOnly(
                                    sorted[index - 1].createdAt!.toLocal(),
                                  )))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16, top: 4),
                          child: Text(
                            localizedSubmissionDay(
                              context,
                              sorted[index].createdAt!,
                              DateTime.now(),
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: p.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ResidentReportMessageBubble(
                        key: ValueKey(sorted[index].id),
                        report: report,
                        sender: sorted[index].sender,
                        message: sorted[index].message,
                        createdAt: sorted[index].createdAt,
                        imageUrl: sorted[index].imageUrl,
                        photoObservedAt: sorted[index].photoObservedAt,
                      ),
                    ],
                    if (report.clarificationRepliedAt != null &&
                        report.reviewOpen &&
                        !report.awaitsResident)
                      ReportPanel(
                        tint: p.passable.withValues(alpha: .08),
                        child: Text(
                          tr(
                            context,
                            'Reply sent. Waiting for barangay review.',
                          ),
                          style: TextStyle(color: p.passable, height: 1.5),
                        ),
                      ),
                    if (report.clarificationRequestId != null &&
                        !report.awaitsResident)
                      _clarificationButton(context, report, false),
                  ],
                )
              : ListView(
                  key: ValueKey('resident-report-${report.id}'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    notices(),
                    if (!report.reviewOpen) ...[
                      ReportReviewSummary(report: report, compact: true),
                      const SizedBox(height: 12),
                    ],
                    ResidentReportEvidenceCard(
                      report: report,
                      road: widget.road,
                    ),
                    const SizedBox(height: 14),
                    ReportPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          title('Where your report is now'),
                          ReportStatusProgress(report: report, resident: true),
                          if (report.reviewOpen)
                            Text(
                              tr(
                                context,
                                report.awaitsResident
                                    ? 'Waiting for your reply in Messages.'
                                    : report.clarificationRepliedAt != null
                                    ? 'Reply sent. Waiting for barangay review.'
                                    : report.status == 'under_review'
                                    ? 'Under barangay review'
                                    : 'Waiting for barangay review',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: report.awaitsResident
                                    ? p.onWarningContainer
                                    : p.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.road != null) ...[
                      const SizedBox(height: 14),
                      ReportPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            title('Latest recorded road condition'),
                            Text(
                              tr(
                                context,
                                AdminRoadAssessment(
                                  widget.road!,
                                  DateTime.now(),
                                  SimulatedWeatherService.instance.currentState,
                                ).summaryTitle,
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: p.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${tr(context, 'Updated')}: ${localizedDateTime(context, widget.road!.updatedAt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: p.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr(
                                context,
                                'This is separate from the review of your observation. Conditions may have changed.',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: p.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (ReportFreshness.isOutdated(report, DateTime.now()))
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          tr(
                            context,
                            'This observation is old. Check the latest road condition before travel.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: p.warning,
                          ),
                        ),
                      ),
                    ReportFollowupLink(report: report),
                  ],
                ),
        ),
        if (_messages &&
            report.awaitsResident &&
            report.clarificationRequestId != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(
                top: BorderSide(color: p.outlineVariant.withValues(alpha: .4)),
              ),
            ),
            child: FilledButton.icon(
              key: const ValueKey('report-question-action'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportClarificationScreen(
                    reportId: report.id,
                    report: report,
                  ),
                ),
              ),
              icon: const Icon(Icons.reply_rounded, size: 18),
              label: Text(tr(context, 'Reply to the question')),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
      ],
    );
  }
}

class ReportUpdatesHeader extends StatelessWidget {
  const ReportUpdatesHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.forum_outlined, size: 20, color: p.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'Report conversation'),
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: p.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    context,
                    'Private messages and report decisions. Newest first.',
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 1.4,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReportUpdateTimelineEntry extends StatelessWidget {
  final AdminUpdateMessage message;
  final bool first, last;
  const ReportUpdateTimelineEntry({
    super.key,
    required this.message,
    this.first = false,
    this.last = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final resident = message.sender == 'Resident clarification';
    final color = resident ? p.onSurfaceVariant : p.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CustomPaint(
        painter: _UpdateLine(color: color, first: first, last: last),
        child: Padding(
          padding: const EdgeInsets.only(left: 32),
          child: ReportConversationCard(
            title: resident ? 'Resident reply' : message.sender,
            message: message.message,
            resident: resident,
            time: message.createdAt == null
                ? tr(context, 'Confirming time...')
                : localizedDateTime(context, message.createdAt!),
            attachment: message.imageUrl == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SafeImage(
                          imageUrl: message.imageUrl!,
                          height: 180,
                        ),
                      ),
                      if (message.photoObservedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            '${tr(context, 'Photo observation time')}: ${localizedDateTime(context, message.photoObservedAt!)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: p.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _UpdateLine extends CustomPainter {
  final Color color;
  final bool first, last;
  const _UpdateLine({
    required this.color,
    required this.first,
    required this.last,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .4)
      ..strokeWidth = 1.5;
    const dot = Offset(17, 22);
    if (!first)
      canvas.drawLine(const Offset(17, 0), const Offset(17, 16), paint);
    if (!last)
      canvas.drawLine(const Offset(17, 28), Offset(17, size.height), paint);
    canvas.drawCircle(dot, 7, Paint()..color = color.withValues(alpha: .12));
    canvas.drawCircle(dot, 4.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_UpdateLine old) =>
      color != old.color || first != old.first || last != old.last;
}
