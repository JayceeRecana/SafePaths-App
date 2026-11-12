import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../models/road_status.dart';
import '../theme/app_palette.dart';
import 'report_workflow_ui.dart';
import 'road_condition_overview.dart' show residentRoadTitle;

/// Current-condition reminders, separate from the report review queue.
/// The caller owns both selection and authenticated road navigation.
class AdminRoadCheckSection extends StatelessWidget {
  final List<RoadStatus> roads;
  final ValueChanged<RoadStatus> onOpen;
  const AdminRoadCheckSection({
    super.key,
    required this.roads,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    if (roads.isEmpty) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    return ReportPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.edit_road_outlined,
                  size: 20,
                  color: p.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(context, 'Check current road conditions'),
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                    color: p.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: p.warningContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${roads.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.onWarningContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              context,
              'Use CCTV or a field check to confirm the current condition, then update the road status.',
            ),
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.5,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          for (final road in roads) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              decoration: BoxDecoration(
                color: p.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: p.outlineVariant.withValues(alpha: .35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    residentRoadTitle(road.name) == 'Unnamed residential road'
                        ? tr(context, 'Unnamed residential road')
                        : residentRoadTitle(road.name),
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: p.onWarningContainer,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          tr(context, switch (road.communityCondition) {
                            'outdated' =>
                              'Earlier observations are outdated. A new road check is needed.',
                            'under_verification' =>
                              'Resident observations still need a current road check.',
                            _ =>
                              'A resident reported flooding. Check the road as it is now.',
                          }),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.5,
                            color: p.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => onOpen(road),
                      icon: const Icon(Icons.arrow_forward, size: 17),
                      label: Text(
                        tr(context, 'Open road details'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            tr(context, 'Road updates and report decisions are separate.'),
            style: GoogleFonts.inter(
              fontSize: 11,
              height: 1.5,
              color: p.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
