import '../theme/app_palette.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../services/report_submission_coordinator.dart';

class ReportUploadProgress extends StatelessWidget {
  final ReportSubmissionPhase phase;
  final double? progress;
  const ReportUploadProgress({super.key, required this.phase, this.progress});
  @override
  Widget build(BuildContext context) {
    if (![
      ReportSubmissionPhase.processing,
      ReportSubmissionPhase.uploading,
      ReportSubmissionPhase.saving,
    ].contains(phase)) {
      return const SizedBox.shrink();
    }
    final value = progress != null && progress!.isFinite
        ? progress!.clamp(0.0, 1.0)
        : null;
    final label = switch (phase) {
      ReportSubmissionPhase.processing => 'Processing photo...',
      ReportSubmissionPhase.uploading =>
        value == null
            ? 'Uploading photo...'
            : '${tr(context, 'Uploading photo')}: ${(value * 100).floor()}%',
      _ => 'Saving report...',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, label),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppPalette.of(context).onSurface,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: phase == ReportSubmissionPhase.uploading ? value : null,
            semanticsLabel: tr(context, label),
          ),
          if (phase == ReportSubmissionPhase.saving)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                tr(
                  context,
                  'Keep this screen open until your report is confirmed.',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
