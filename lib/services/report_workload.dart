import '../models/user_report.dart';
import '../utils/time_utils.dart';

// Shared by Dashboard and Reports: urgency first, then oldest submitted work.
// Trust/confidence is evidence context, never a hidden queue priority.
int compareReportWorkload(UserReport a, UserReport b) {
  if (a.isEmergency != b.isEmergency) return a.isEmergency ? -1 : 1;
  if (a.awaitsResident != b.awaitsResident) return a.awaitsResident ? 1 : -1;
  final validA = TimeUtils.hasRecordedTime(a.createdAt),
      validB = TimeUtils.hasRecordedTime(b.createdAt);
  if (validA != validB) return validA ? -1 : 1;
  final age = a.createdAt.compareTo(b.createdAt);
  return age != 0 ? age : a.id.compareTo(b.id);
}

class ReportWorkload {
  final List<UserReport> open;
  ReportWorkload(Iterable<UserReport> records)
    : open = {
        for (final r in records.where((r) => r.reviewOpen)) r.id: r,
      }.values.toList()..sort(compareReportWorkload);
  int get needsAdmin => open.where((r) => r.needsAdminReview).length;
  int get waiting => open.where((r) => r.awaitsResident).length;
  int get urgent => open.where((r) => r.isEmergency).length;
  UserReport? get oldest {
    final records =
        open
            .where(
              (r) =>
                  r.needsAdminReview && TimeUtils.hasRecordedTime(r.createdAt),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return records.firstOrNull;
  }
}
