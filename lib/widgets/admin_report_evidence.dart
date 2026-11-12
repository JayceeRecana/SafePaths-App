import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../l10n/formatters.dart';
import '../models/user_report.dart';
import '../models/road_status.dart';
import '../theme/app_palette.dart';
import '../utils/geo_utils.dart';
import '../utils/time_utils.dart';
import '../services/road_location_preview.dart';
import 'road_location_preview.dart';
import 'report_submission_preview.dart';
import 'report_workflow_ui.dart';

class ReportedLocationEvidence {
  final double lat, lng;
  final String? source;
  const ReportedLocationEvidence(this.lat, this.lng, this.source);
  static ReportedLocationEvidence? from(UserReport report) {
    final lat = report.location?['lat'], lng = report.location?['lng'];
    if (lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180)
      return null;
    final raw = report.location?['source'];
    final source = raw is String ? raw.trim().toLowerCase() : null;
    return ReportedLocationEvidence(lat.toDouble(), lng.toDouble(), source);
  }

  GeoCoord get point => GeoCoord(lat, lng);
  String get displayed =>
      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  String get copyValue => '$lat, $lng';
  String get sourceLabel => switch (source) {
    'gps' => 'GPS location',
    'manual' => 'Map pin',
    _ => 'Location source not recorded',
  };
}

class AdminReportEvidenceCard extends StatelessWidget {
  final UserReport report;
  final RoadStatus? road;
  final bool enabled;
  final String? reporterName, reporterPhotoUrl;
  final int? reporterTrust;
  final VoidCallback? onViewMap;
  const AdminReportEvidenceCard({
    super.key,
    required this.report,
    this.road,
    this.enabled = true,
    this.reporterName,
    this.reporterPhotoUrl,
    this.reporterTrust,
    this.onViewMap,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        evidence = submittedReportEvidence(report);
    final location = ReportedLocationEvidence.from(evidence);
    final hasPhoto = evidence.imageUrl?.trim().isNotEmpty == true;
    String time(DateTime? value) => TimeUtils.hasRecordedTime(value)
        ? localizedDateTime(context, value!)
        : tr(context, 'Not recorded');
    Widget fact(IconData icon, String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: p.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, title),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    height: 1.5,
                    color: p.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.5,
                    color: p.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ReportPanel(
      key: ValueKey('submission-preview-${report.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, 'What the resident sent'),
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (hasPhoto) ...[
            ReportPhotoThumbnail(
              report: evidence,
              width: double.infinity,
              height: 190,
              showExpandBadge: true,
            ),
            const SizedBox(height: 12),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: fact(
                Icons.image_outlined,
                'Photo',
                tr(context, 'No photo attached'),
              ),
            ),
          ReportRetainedPhotoNotice(report: evidence),
          Text(
            evidence.description.isNotEmpty
                ? evidence.description
                : tr(context, 'No description provided.'),
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.5,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: p.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        tr(context, 'Reported location'),
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: p.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (location != null) ...[
                  SelectableText(
                    location.displayed,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(context, location.sourceLabel),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack =
                          constraints.maxWidth < 290 ||
                          MediaQuery.textScalerOf(context).scale(12) > 16;
                      final copy = OutlinedButton.icon(
                        onPressed: enabled
                            ? () async {
                                await Clipboard.setData(
                                  ClipboardData(text: location.copyValue),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr(context, 'Coordinates copied.'),
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: Text(
                          tr(context, 'Copy coordinates'),
                          textAlign: TextAlign.center,
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 46),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          textStyle: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                      final map = FilledButton.tonalIcon(
                        onPressed: !enabled
                            ? null
                            : onViewMap ??
                                  () => showDialog<void>(
                                    context: context,
                                    builder: (_) => ReportPhotoViewer(
                                      child: ReportLocationMapDialog(
                                        report: evidence,
                                        road: road,
                                      ),
                                    ),
                                  ),
                        icon: const Icon(Icons.map_outlined, size: 17),
                        label: Text(
                          tr(context, 'View on map'),
                          textAlign: TextAlign.center,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.primaryContainer,
                          foregroundColor: p.onPrimaryContainer,
                          minimumSize: const Size(48, 46),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          textStyle: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                      return stack
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [map, const SizedBox(height: 8), copy],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: copy),
                                const SizedBox(width: 8),
                                Expanded(child: map),
                              ],
                            );
                    },
                  ),
                ] else
                  Text(
                    tr(context, 'Not recorded'),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  tr(context, 'Reported position; not verified photo GPS.'),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    height: 1.5,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          fact(
            Icons.water_drop_outlined,
            'Resident-selected flood level',
            const ['Low', 'Medium', 'High'].contains(evidence.severity)
                ? tr(context, evidence.severity)
                : tr(context, 'Not recorded'),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
          const SizedBox(height: 14),
          Text(
            tr(context, 'Report information'),
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          fact(
            Icons.visibility_outlined,
            'Resident observation time',
            time(evidence.observedAt),
          ),
          Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
          fact(Icons.send_outlined, 'Submitted', time(evidence.createdAt)),
          Divider(height: 1, color: p.outlineVariant.withValues(alpha: .4)),
          ReportReference(reportId: report.id),
          ReportEvidenceContext(
            report: report,
            reporterName: reporterName,
            reporterPhotoUrl: reporterPhotoUrl,
            reporterTrust: reporterTrust,
            showReporterAvatar: true,
            showReporterContext: true,
            showObservationDetails: false,
          ),
          if (report.originalSubmission != null)
            Text(
              tr(context, 'Original submission'),
              style: GoogleFonts.inter(fontSize: 10, color: p.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class ReportLocationMapDialog extends StatelessWidget {
  final UserReport report;
  final RoadStatus? road;
  final RoadPreviewCapture Function()? capture;
  const ReportLocationMapDialog({
    super.key,
    required this.report,
    this.road,
    this.capture,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        location = ReportedLocationEvidence.from(report);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'Reported location'),
                      style: GoogleFonts.manrope(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: p.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, 'Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      reportRoadName(report, road: road),
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      location?.displayed ?? tr(context, 'Not recorded'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: p.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (location != null)
                      RoadLocationPreview(
                        roads: [if (road != null) road!],
                        reportedPoint: location.point,
                        height: 280,
                        capture: capture,
                      ),
                    if (road == null ||
                        GeoUtils.extractSegments(road!.geometry).isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          tr(
                            context,
                            'Road geometry is unavailable. Only the reported point can be shown.',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 1.5,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'Reported position; not verified photo GPS.'),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        height: 1.5,
                        color: p.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
