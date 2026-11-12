import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../models/user_report.dart';
import '../theme/app_palette.dart';
import 'report_submission_preview.dart';
import 'report_workflow_ui.dart';

/// Compact context for report actions; the complete evidence stays in Report.
class AdminReportContextCard extends StatelessWidget {
  final UserReport report;
  final bool showReference;
  const AdminReportContextCard({
    super.key,
    required this.report,
    this.showReference = true,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        evidence = submittedReportEvidence(report);
    final name = reportRoadName(evidence);
    return ReportPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (evidence.imageUrl?.trim().isNotEmpty == true) ...[
                ReportPhotoThumbnail(report: evidence, width: 46, height: 46),
                const SizedBox(width: 10),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: p.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name == 'Unnamed residential road'
                          ? tr(context, name)
                          : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: p.onSurface,
                      ),
                    ),
                    if (evidence.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        evidence.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          height: 1.45,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (showReference) ...[
            const SizedBox(height: 6),
            ReportReference(reportId: report.id),
          ],
        ],
      ),
    );
  }
}

/// Shared visual treatment only: callers retain their draft/save validation.
class AdminReportEditorCard extends StatelessWidget {
  final TextEditingController controller;
  final String title, hint;
  final bool enabled, question;
  final ValueChanged<String> onChanged;
  const AdminReportEditorCard({
    super.key,
    required this.controller,
    required this.title,
    required this.hint,
    required this.onChanged,
    this.enabled = true,
    this.question = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        accent = question ? p.onWarningContainer : p.primary;
    return ReportPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                question
                    ? Icons.question_answer_outlined
                    : Icons.edit_note_rounded,
                size: 19,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(context, title),
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: p.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: enabled,
            maxLength: 1000,
            minLines: 2,
            maxLines: 6,
            onChanged: onChanged,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.5,
              color: p.onSurface,
            ),
            decoration: InputDecoration(
              hintText: tr(context, hint),
              hintStyle: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: p.onSurfaceVariant,
              ),
              filled: true,
              fillColor: p.surfaceContainerLow,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: p.outlineVariant.withValues(alpha: .4),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: p.outlineVariant.withValues(alpha: .4),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: question
                    ? Text(
                        tr(context, 'Minimum 10 characters'),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: p.onSurfaceVariant,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Text(
                '${controller.text.length}/1000',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: p.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
