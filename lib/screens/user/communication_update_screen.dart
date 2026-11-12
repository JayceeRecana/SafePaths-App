import '../../widgets/safe_image.dart';
import '../../widgets/resident_alert_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../models/broadcast_alert.dart';
import '../../l10n/app_strings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_environment.dart';
import '../../widgets/report_message_thread.dart';

/// Shows current authorized data, never notification text as a current outcome.
class CommunicationUpdateScreen extends StatelessWidget {
  final String kind, id;
  const CommunicationUpdateScreen({
    super.key,
    required this.kind,
    required this.id,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: kind == 'feedback'
        ? AppBar(title: const Text('Feedback update'))
        : const AppTopBar(
            title: 'Area alert',
            showBackButton: true,
            showProfile: false,
            showSettingsAction: false,
          ),
    body: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, auth) {
        final user = auth.data;
        if (user == null ||
            !user.emailVerified ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
          return const Center(
            child: Text('Sign in with the correct verified account.'),
          );
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey('${user.uid}:$kind:$id'),
          stream: FirebaseFirestore.instance
              .collection(kind == 'feedback' ? 'feedbacks' : 'alerts')
              .doc(id)
              .snapshots(includeMetadataChanges: true),
          builder: (context, snapshot) {
            if (snapshot.hasError ||
                snapshot.hasData && !snapshot.data!.exists) {
              return const Center(
                child: Text(
                  'This update is unavailable. Refresh your history.',
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!.data()!;
            if (FirebaseAuth.instance.currentUser?.uid != user.uid ||
                kind == 'feedback' && data['userId'] != user.uid ||
                kind != 'feedback' &&
                    data['studyArea'] != AppEnvironment.area.id) {
              return const Center(
                child: Text(
                  'This update is unavailable for this account or area.',
                ),
              );
            }
            if (kind != 'feedback') {
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (snapshot.data!.metadata.isFromCache)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        tr(
                          context,
                          'Saved information; reconnect to check the latest status.',
                        ),
                      ),
                    ),
                  ResidentAlertCard(
                    alert: BroadcastAlert.fromJson({...data, 'id': id}),
                  ),
                  const SizedBox(height: 16),
                  const AlertRoadReminder(),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (snapshot.data!.metadata.isFromCache)
                  const Text(
                    'Saved information; reconnect to check the latest status.',
                  ),
                Text(
                  kind == 'feedback'
                      ? (data['category'] as String? ?? 'Feedback')
                      : (data['title'] as String? ?? 'Alert'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (kind == 'feedback')
                  Text(
                    'Status: ${data['status'] == 'resolved' ? 'Closed (${data['resolutionOutcome'] ?? 'recorded'})' : data['status'] ?? 'new'}',
                  ),
                const SizedBox(height: 12),
                Text(
                  kind == 'feedback'
                      ? (data['comments'] as String? ?? '')
                      : (data['message'] as String? ?? ''),
                ),
                if (kind == 'feedback' && data['imageUrl'] is String)
                  SafeImage(
                    imageUrl: data['imageUrl'] as String,
                    mediaResourceId: id,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                if (kind == 'feedback') ...[
                  if (data['hasAdminUpdates'] != true &&
                      data['adminReply'] is String)
                    Text(data['adminReply'] as String),
                  ReportMessageThread(reportId: id, feedback: true),
                ],
              ],
            );
          },
        );
      },
    ),
  );
}
