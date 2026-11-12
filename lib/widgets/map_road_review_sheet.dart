import 'package:flutter/material.dart';
import '../models/road_status.dart';
import '../services/admin_report_service.dart';
import 'admin_review_dialog.dart';

/// Reuses the same checked, conflict-aware save as the list editor.
/// The map remains visible above the form; typing expands the available form.
Future<AdminActionResult?> showMapRoadReview(
  BuildContext context,
  RoadStatus road,
) => showModalBottomSheet<AdminActionResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.transparent,
  isDismissible: false,
  enableDrag: false,
  builder: (context) => LayoutBuilder(
    builder: (context, bounds) {
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final available = (bounds.maxHeight - keyboard).clamp(
        0.0,
        bounds.maxHeight,
      );
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: keyboard > 0 ? available : available * .64,
          child: AdminReviewDialog(
            roadIds: [road.id],
            previewRoad: road,
            mapSheet: true,
            quickConditions: true,
            showRoadSettings: true,
          ),
        ),
      );
    },
  ),
);
