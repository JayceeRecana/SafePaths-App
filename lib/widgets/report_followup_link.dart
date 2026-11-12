import 'package:flutter/material.dart';
import '../config/app_environment.dart';
import '../l10n/app_strings.dart';
import '../models/user_report.dart';
import '../services/report_followup_service.dart';
import '../screens/user/report_followup_screen.dart';

class ReportFollowupLink extends StatelessWidget {
  final UserReport report;
  final bool readOnly;
  final String label;
  const ReportFollowupLink({
    super.key,
    required this.report,
    this.readOnly = false,
    this.label = 'View condition history',
  });
  @override
  Widget build(BuildContext context) {
    if (!AppEnvironment.sparkFollowupsEnabled ||
        report.roadId == null ||
        report.incidentId == null)
      return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.isFollowup)
          Text(
            '${tr(context, 'Follow-up')}: ${tr(context, followupChangeLabel(report.conditionChange))}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReportFollowupScreen(
                rootReportId: report.historyRootId,
                readOnly: readOnly,
              ),
            ),
          ),
          icon: const Icon(Icons.history_outlined),
          label: Text(tr(context, label)),
        ),
      ],
    );
  }
}
