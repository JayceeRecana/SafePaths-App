import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/user_report.dart';
import '../../models/road_status.dart';
import '../../widgets/report_message_thread.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/report_workflow_ui.dart';
import '../../theme/app_palette.dart';

/// Fetches the current report instead of trusting stale notification text.
class ReportUpdateScreen extends StatelessWidget {
  final String reportId;
  const ReportUpdateScreen({super.key, required this.reportId});
  @override
  Widget build(BuildContext context) {
    Widget waiting(Widget child) => Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'Updates on your report'),
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
      ),
      body: child,
    );
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, auth) {
        final user = auth.data;
        if (user == null || !user.emailVerified || user.isAnonymous)
          return waiting(
            Center(
              child: Text(
                tr(
                  context,
                  'Sign in with the account that submitted this report.',
                ),
              ),
            ),
          );
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey('${user.uid}:$reportId'),
          stream: FirebaseFirestore.instance
              .collection('reports')
              .doc(reportId)
              .snapshots(includeMetadataChanges: true),
          builder: (context, snapshot) {
            if (snapshot.hasData &&
                !snapshot.data!.exists &&
                snapshot.data!.metadata.isFromCache) {
              final p = AppPalette.of(context);
              return waiting(
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ReportPanel(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_sync_outlined,
                            size: 28,
                            color: p.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr(context, 'Report not loaded yet'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: p.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(
                              context,
                              'This report is not saved on this device yet. Connect to the internet to load its latest details.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: p.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            if (snapshot.hasError ||
                (snapshot.hasData && !snapshot.data!.exists))
              return waiting(
                Center(
                  child: Text(
                    tr(
                      context,
                      'This report is unavailable. Check your report history.',
                    ),
                  ),
                ),
              );
            if (!snapshot.hasData)
              return waiting(const Center(child: CircularProgressIndicator()));
            final data = snapshot.data!.data()!;
            if (data['userId'] != user.uid ||
                FirebaseAuth.instance.currentUser?.uid != user.uid)
              return waiting(
                Center(
                  child: Text(
                    tr(
                      context,
                      'Sign in with the account that submitted this report.',
                    ),
                  ),
                ),
              );
            UserReport report;
            try {
              report = UserReport.fromJson({...data, 'id': reportId});
            } catch (_) {
              return waiting(
                Center(
                  child: Text(
                    tr(
                      context,
                      'This report is unavailable. Check your report history.',
                    ),
                  ),
                ),
              );
            }
            Widget details(RoadStatus? road) => ReportUpdatesPage(
              key: ValueKey('notification-updates-${user.uid}:$reportId'),
              reportId: reportId,
              report: report,
              road: road,
              showReviewSummary: true,
              reportIsLive: true,
              reportFromCache: snapshot.data!.metadata.isFromCache,
              hasServerUpdates: report.hasAdminUpdates,
              legacyReplies: report.adminReplies.isNotEmpty
                  ? report.adminReplies
                  : [
                      if (report.adminReply?.trim().isNotEmpty == true)
                        ReportReply(
                          message: report.adminReply!,
                          timestamp: report.reviewedAt ?? report.createdAt,
                        ),
                    ],
            );
            if (report.roadId == null) return details(null);
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('roads')
                  .doc(report.roadId)
                  .snapshots(),
              builder: (context, road) {
                RoadStatus? current;
                if (road.hasData && road.data!.exists) {
                  try {
                    current = RoadStatus.fromJson({
                      ...road.data!.data()!,
                      'id': report.roadId,
                    });
                  } catch (_) {}
                }
                return details(current);
              },
            );
          },
        );
      },
    );
  }
}
