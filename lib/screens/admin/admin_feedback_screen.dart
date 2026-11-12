import '../../widgets/communication_admin_dialog.dart';
import '../../widgets/report_message_thread.dart';
import '../../widgets/feed_status_notice.dart';
import '../../services/sync_health.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/safe_image.dart';
import '../../models/feedback_model.dart';
import '../../services/notification_service.dart';
import '../../config/app_environment.dart';
import '../../services/user_service.dart';
import '../../utils/time_utils.dart';

class AdminFeedbackScreen extends StatefulWidget {
  final Stream<QuerySnapshot>? feedbackStream;
  const AdminFeedbackScreen({super.key, this.feedbackStream});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  String _statusFilter = 'new'; // 'new', 'reviewed', 'resolved'
  late Stream<QuerySnapshot> _feedback;
  Stream<QuerySnapshot> _openFeed() =>
      widget.feedbackStream ??
      FirebaseFirestore.instance
          .collection('feedbacks')
          .orderBy('timestamp', descending: true)
          .snapshots(includeMetadataChanges: true);
  @override
  void initState() {
    super.initState();
    _feedback = _openFeed();
  }

  void _retry() => setState(() => _feedback = _openFeed());

  Widget _withFreshness(AsyncSnapshot<QuerySnapshot> snapshot, Widget child) {
    final condition = snapshot.connectionState == ConnectionState.waiting
        ? SyncCondition.connecting
        : snapshot.data?.metadata.isFromCache == true
        ? SyncCondition.cached
        : SyncCondition.live;
    if (condition == SyncCondition.live) return child;
    return Column(
      children: [
        FeedStatusNotice(
          condition: condition,
          isEmpty: false,
          emptyMessage: '',
          onRetry: _retry,
        ),
        Expanded(child: child),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).surface,
      appBar: AppTopBar(
        title: tr(context, 'User Feedback'),
        showBackButton: Navigator.canPop(context),
        onBackPressed: Navigator.canPop(context)
            ? () => Navigator.pop(context)
            : null,
        showProfile: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'new', label: Text(tr(context, 'New'))),
                  ButtonSegment(
                    value: 'reviewed',
                    label: Text(tr(context, 'Reviewed')),
                  ),
                  ButtonSegment(
                    value: 'resolved',
                    label: Text(tr(context, 'Resolved')),
                  ),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() => _statusFilter = newSelection.first);
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppPalette.of(
                    context,
                  ).primaryContainer,
                  selectedForegroundColor: AppPalette.of(context).primary,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _feedback,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return FeedStatusNotice(
                    condition: SyncCondition.failed,
                    isEmpty: true,
                    emptyMessage: '',
                    onRetry: _retry,
                  );

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: AppPalette.of(context).primary,
                    ),
                  );
                }

                final allDocs = snapshot.data?.docs ?? [];
                if (allDocs.isEmpty &&
                    snapshot.data?.metadata.isFromCache == true)
                  return FeedStatusNotice(
                    condition: SyncCondition.cached,
                    isEmpty: true,
                    emptyMessage: '',
                    onRetry: _retry,
                  );
                final docs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status'] as String? ?? 'new';
                  return status == _statusFilter;
                }).toList();

                if (docs.isEmpty) {
                  return _withFreshness(
                    snapshot,
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.feedback_outlined,
                            size: 48,
                            color: AppPalette.of(context).outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No feedback in $_statusFilter.',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return _withFreshness(
                  snapshot,
                  ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final feedback = FeedbackModel.fromJson(
                        data,
                        docs[index].id,
                      );

                      return _FeedbackCard(feedback: feedback);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final FeedbackModel feedback;

  const _FeedbackCard({required this.feedback});

  String _getTimeAgo(DateTime dateTime) => TimeUtils.getTimeAgo(dateTime);

  void _showResolveDialog(BuildContext context) {
    if (AppEnvironment.sparkCommunicationsEnabled) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            CommunicationAdminDialog(kind: 'feedback', id: feedback.id),
      );
      return;
    }
    final noteController = TextEditingController(
      text: feedback.adminReply ?? '',
    );
    bool notifyUser = AppEnvironment.pushEnabled && feedback.userId != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: AppPalette.of(context).primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                tr(context, 'Resolve Feedback'),
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'Send a closure note or reply to the user:'),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppPalette.of(context).onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  style: GoogleFonts.inter(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: tr(context, 'Add reply message...'),
                    filled: true,
                    fillColor: AppPalette.of(context).surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppPalette.of(context).outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        label: Text(
                          tr(context, 'Acknowledgement'),
                          style: GoogleFonts.inter(fontSize: 11),
                        ),
                        backgroundColor: AppPalette.of(
                          context,
                        ).surfaceContainerLow,
                        padding: EdgeInsets.zero,
                        onPressed: () => setModalState(
                          () => noteController.text =
                              'Thank you. Your feedback has been received for review.',
                        ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        label: Text(
                          tr(context, 'Under review'),
                          style: GoogleFonts.inter(fontSize: 11),
                        ),
                        backgroundColor: AppPalette.of(
                          context,
                        ).surfaceContainerLow,
                        padding: EdgeInsets.zero,
                        onPressed: () => setModalState(
                          () => noteController.text =
                              'Your feedback is under review. We will record the outcome here.',
                        ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        label: Text(
                          tr(context, 'Forwarded to Barangay 📋'),
                          style: GoogleFonts.inter(fontSize: 11),
                        ),
                        backgroundColor: AppPalette.of(
                          context,
                        ).surfaceContainerLow,
                        padding: EdgeInsets.zero,
                        onPressed: () => setModalState(
                          () => noteController.text =
                              'Your feedback has been noted and forwarded to the local Barangay Operations.',
                        ),
                      ),
                    ],
                  ),
                ),
                if (feedback.userId != null) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      tr(context, 'Send Push Notification to Citizen'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: notifyUser,
                    activeTrackColor: AppPalette.of(context).primary,
                    onChanged: AppEnvironment.pushEnabled
                        ? (val) => setModalState(() => notifyUser = val)
                        : null,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                tr(context, 'Cancel'),
                style: GoogleFonts.inter(
                  color: AppPalette.of(context).onSurfaceVariant,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.of(context).primary,
              ),
              onPressed: () async {
                final note = noteController.text.trim();
                Navigator.pop(dialogCtx);

                final adminUid = await UserService.getUserId();
                await FirebaseFirestore.instance
                    .collection('feedbacks')
                    .doc(feedback.id)
                    .update({
                      'status': 'resolved',
                      'adminReply': note.isNotEmpty ? note : null,
                      'reviewedAt': FieldValue.serverTimestamp(),
                      'adminUid': adminUid,
                    });

                PushResult? pushResult;
                if (notifyUser && feedback.userId != null && note.isNotEmpty) {
                  try {
                    pushResult = await NotificationService.instance.sendPushToUser(
                      userId: feedback.userId!,
                      title: tr(context, 'SafePaths Feedback Resolved'),
                      body:
                          'Your feedback on ${feedback.category} has been addressed: "$note"',
                      data: {
                        'type': 'feedback_resolved',
                        'feedbackId': feedback.id,
                      },
                    );
                  } catch (e) {
                    debugPrint('[AdminFeedback] Push failed: $e');
                  }
                }

                if (context.mounted) {
                  String msg = 'Feedback resolved and saved.';
                  if (pushResult != null) {
                    if (pushResult.status == PushStatus.sent) {
                      msg =
                          'Feedback saved; notification accepted for sending. Phone receipt is unconfirmed.';
                    } else if (pushResult.status == PushStatus.noTokens) {
                      msg = 'Feedback resolved (User has no active push token)';
                    }
                  }
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                }
              },
              child: Text(tr(context, 'Resolve & Save')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppPalette.of(context).outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.of(context).primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        feedback.category.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.of(context).primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      _getTimeAgo(feedback.timestamp),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: List.generate(5, (i) {
                    return Icon(
                      i < feedback.rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: i < feedback.rating
                          ? Colors.amber
                          : AppPalette.of(context).outlineVariant,
                      size: 20,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  '"${feedback.comments}"',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.of(context).onSurface,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (feedback.userId != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'User ID: ${feedback.userId!.length >= 8 ? feedback.userId!.substring(0, 8) : feedback.userId}...',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppPalette.of(context).onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                if (feedback.adminReply != null &&
                    feedback.adminReply!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppPalette.of(
                          context,
                        ).primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 14,
                              color: AppPalette.of(context).primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tr(context, 'Admin Response:'),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.of(context).primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          feedback.adminReply!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppPalette.of(context).onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (AppEnvironment.sparkCommunicationsEnabled)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            ReportMessageThread(
                              reportId: feedback.id,
                              isAdmin: true,
                              feedback: true,
                            ),
                            FilledButton.icon(
                              onPressed: () => _showResolveDialog(context),
                              icon: const Icon(Icons.rate_review_outlined),
                              label: const Text('Review / reply'),
                            ),
                          ],
                        ),
                      ),
                    if (!AppEnvironment.sparkCommunicationsEnabled &&
                        feedback.status == 'new')
                      TextButton.icon(
                        onPressed: () => FirebaseFirestore.instance
                            .collection('feedbacks')
                            .doc(feedback.id)
                            .update({'status': 'reviewed'}),
                        icon: const Icon(Icons.visibility),
                        label: Text(tr(context, 'Mark Reviewed')),
                      ),
                    if (!AppEnvironment.sparkCommunicationsEnabled &&
                        feedback.status == 'reviewed') ...[
                      TextButton.icon(
                        onPressed: () => FirebaseFirestore.instance
                            .collection('feedbacks')
                            .doc(feedback.id)
                            .update({'status': 'new'}),
                        icon: const Icon(Icons.undo),
                        label: Text(tr(context, 'Move to New')),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.of(context).primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _showResolveDialog(context),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(tr(context, 'Reply & Resolve')),
                      ),
                    ],
                    if (!AppEnvironment.sparkCommunicationsEnabled &&
                        feedback.status == 'resolved') ...[
                      TextButton.icon(
                        onPressed: () => _showResolveDialog(context),
                        icon: const Icon(Icons.edit_note),
                        label: Text(tr(context, 'Edit Reply')),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => FirebaseFirestore.instance
                            .collection('feedbacks')
                            .doc(feedback.id)
                            .update({'status': 'reviewed'}),
                        icon: const Icon(Icons.refresh),
                        label: Text(tr(context, 'Reopen')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (feedback.imageUrl != null && feedback.imageUrl!.isNotEmpty) ...[
            const Divider(height: 1, thickness: 1),
            SafeImage(
              imageUrl: feedback.imageUrl,
              mediaResourceId: feedback.id,
              width: double.infinity,
              height: 200,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
