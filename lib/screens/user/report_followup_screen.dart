import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/report_message_thread.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/formatters.dart';
import '../../models/user_report.dart';
import '../../services/report_followup_service.dart';
import '../../services/report_photo_uploader.dart';
import '../../services/report_submission_repository.dart';
import '../../services/spark_proof_client.dart';
import '../../theme/app_palette.dart';
import '../../utils/report_image.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/report_submission_preview.dart';
import '../../widgets/report_workflow_ui.dart';

class ReportFollowupScreen extends StatefulWidget {
  final String rootReportId;
  final bool readOnly;
  final String? Function()? currentViewer;
  final Stream<String?>? viewerChanges;
  final Future<ReportFollowupContext> Function()? loadContext;
  final Future<ReportSaveResult> Function(Map<String, dynamic>)? submitFollowup;
  const ReportFollowupScreen({
    super.key,
    required this.rootReportId,
    this.readOnly = false,
    this.currentViewer,
    this.viewerChanges,
    this.loadContext,
    this.submitFollowup,
  });
  @override
  State<ReportFollowupScreen> createState() => _ReportFollowupScreenState();
}

class _ReportFollowupScreenState extends State<ReportFollowupScreen> {
  final _description = TextEditingController();
  final _uploader = ReportPhotoUploader();
  ReportFollowupContext? _context;
  StreamSubscription<String?>? _auth;
  String? _uid, _change, _severity, _photoReference, _error, _loadError;
  DateTime? _observedAt;
  Uint8List? _photo;
  bool _photoConfirmed = false,
      _loading = true,
      _saving = false,
      _processing = false;
  double? _progress;
  bool _urgent = false;
  int _generation = 0;
  bool _allowLeave = false, _confirmingLeave = false, _accountChanged = false;
  bool _current(int generation) =>
      mounted && !_accountChanged && generation == _generation;
  bool get _hasDraft =>
      !widget.readOnly &&
      (_description.text.trim().isNotEmpty ||
          _photo != null ||
          _change != null ||
          _severity != null ||
          _observedAt != null ||
          _urgent);
  Future<void> _leave() async {
    if (_saving || _processing || _confirmingLeave) return;
    if (_hasDraft) {
      _confirmingLeave = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text(tr(context, 'Discard your unsent changes?')),
          content: Text(
            tr(
              context,
              'Your changes have not been sent. Keep editing to preserve them.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(tr(context, 'Keep editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(tr(context, 'Discard draft')),
            ),
          ],
        ),
      );
      _confirmingLeave = false;
      if (discard != true || !mounted || _saving || _processing) return;
    }
    if (!mounted) return;
    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.loadContext == null || widget.viewerChanges != null) {
      _uid = widget.currentViewer != null
          ? widget.currentViewer!()
          : FirebaseAuth.instance.currentUser?.uid;
      final changes =
          widget.viewerChanges ??
          FirebaseAuth.instance.userChanges().map((user) => user?.uid);
      _auth = changes.listen((uid) {
        if (uid != _uid && mounted && !_accountChanged) {
          _generation++;
          _accountChanged = true;
          _uploader.dispose();
          setState(() {
            _context = null;
            _photo = null;
            _photoReference = null;
            _change = null;
            _severity = null;
            _observedAt = null;
            _urgent = false;
            _photoConfirmed = false;
            _processing = false;
            _saving = false;
            _progress = null;
            _error = null;
            _expandedHistory.clear();
            _description.clear();
            _loading = false;
            _loadError =
                'Account changed. Reopen this report from your own history.';
          });
        }
      });
    }
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _auth?.cancel();
    _uploader.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_accountChanged) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final context =
          await (widget.loadContext?.call() ??
              ReportFollowupService.load(widget.rootReportId));
      if (_current(generation)) setState(() => _context = context);
    } catch (error) {
      if (_current(generation))
        setState(() {
          if (error is SparkProofException &&
              const [
                'permission-denied',
                'unauthenticated',
              ].contains(error.code)) {
            _context = null;
            _description.clear();
            _photo = null;
            _photoReference = null;
            _loadError =
                'This account can no longer open this condition history. Sign in again or return to your own reports.';
          } else {
            _loadError =
                'Condition history could not be refreshed. Your draft is preserved. Retry before submitting.';
          }
        });
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final generation = _generation;
    if (!_current(generation) || _saving || _processing) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr(context, 'Camera')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr(context, 'Gallery')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !_current(generation)) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(source: source);
      if (file == null) return;
      if (await file.length() > maxReportPhotoBytes)
        throw const FormatException(
          'Choose a JPG or PNG photo no larger than 10 MB.',
        );
      final bytes = await compute(prepareReportImage, await file.readAsBytes());
      if (_current(generation))
        setState(() {
          _photo = bytes;
          _photoReference = null;
          _photoConfirmed = false;
        });
    } catch (_) {
      if (_current(generation))
        setState(
          () => _error =
              'This photo could not be prepared. Choose another JPG or PNG image.',
        );
    } finally {
      if (_current(generation)) setState(() => _processing = false);
    }
  }

  Future<void> _chooseTime() async {
    final generation = _generation;
    if (!_current(generation)) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _observedAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now,
    );
    if (!_current(generation) || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_observedAt ?? now),
      builder: twelveHourPickerBuilder,
    );
    if (!_current(generation) || time == null) return;
    setState(
      () => _observedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    if (_accountChanged ||
        widget.readOnly ||
        _saving ||
        _processing ||
        _loading ||
        _loadError != null ||
        _context?.canSubmit != true)
      return;
    if (_change == null ||
        (_change != 'cleared' && _severity == null) ||
        _description.text.trim().isEmpty ||
        _photo != null && !_photoConfirmed) {
      setState(
        () => _error =
            'Choose what changed, describe the current conditions and confirm any attached photo.',
      );
      return;
    }
    final observed = _observedAt ?? DateTime.now();
    final now = DateTime.now();
    if (observed.isAfter(now.add(const Duration(minutes: 1))) ||
        now.difference(observed) >= const Duration(hours: 24)) {
      setState(
        () => _error = 'Choose an observation time within the past 24 hours.',
      );
      return;
    }
    final generation = _generation;
    setState(() {
      _saving = true;
      _error = null;
      _observedAt = observed;
    });
    try {
      if (_photo != null && _photoReference == null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) throw StateError('Please sign in again.');
        final reference = await _uploader.upload(
          'followup:${widget.rootReportId}:$observed',
          uid,
          _photo!,
          (value) {
            if (_current(generation)) setState(() => _progress = value);
          },
        );
        if (!_current(generation)) return;
        _photoReference = reference;
      }
      if (!_current(generation)) return;
      final payload = <String, dynamic>{
        'rootReportId': widget.rootReportId,
        'contextToken': _context!.token,
        'conditionChange': _change,
        'severity': _change == 'cleared' ? 'Low' : _severity,
        'description': _description.text.trim(),
        'isEmergency': _urgent,
        'observedAt': observed.toUtc().toIso8601String(),
        if (_photoReference != null) 'imageUrl': _photoReference,
        if (_photoReference != null) 'photoMatchesObservation': _photoConfirmed,
      };
      await (widget.submitFollowup ?? ReportFollowupService.save)(payload);
      if (!_current(generation)) return;
      setState(() {
        _description.clear();
        _change = null;
        _severity = null;
        _observedAt = null;
        _photo = null;
        _photoReference = null;
        _photoConfirmed = false;
        _urgent = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Follow-up saved for admin review. The road condition has not been changed.',
            ),
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (_current(generation))
        setState(() {
          if (error is SparkProofException && error.code == 'photo-unavailable')
            _photoReference = null;
          _error = error is SparkProofException
              ? error.message
              : 'The follow-up was not confirmed. Keep your draft and retry.';
        });
    } finally {
      if (mounted)
        setState(() {
          _saving = false;
          _progress = null;
        });
    }
  }

  final _expandedHistory = <String>{};

  String _time(DateTime? value) {
    if (value == null || value.year < 2000)
      return tr(context, 'Time not recorded');
    return localizedDateTime(context, value);
  }

  Widget _card(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ReportPanel(padding: const EdgeInsets.all(16), child: child),
  );

  Widget _heading(String text, IconData icon) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: p.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(context, text),
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: p.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    final p = AppPalette.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      hintText: tr(context, hint),
      filled: true,
      fillColor: p.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border(p.outlineVariant.withValues(alpha: .45)),
      enabledBorder: border(p.outlineVariant.withValues(alpha: .45)),
      focusedBorder: border(p.primary),
      hintStyle: GoogleFonts.inter(
        fontSize: 12,
        height: 1.5,
        color: p.onSurfaceVariant,
      ),
    );
  }

  Widget _info(String message, {bool warning = false}) {
    final p = AppPalette.of(context),
        color = warning ? p.onWarningContainer : p.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning ? p.warningContainer : p.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.shield_outlined : Icons.info_outline,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(context, message),
              style: GoogleFonts.inter(fontSize: 11, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _history(UserReport report, {bool original = false}) {
    final p = AppPalette.of(context);
    final earlier =
        original &&
        _context?.root.originalSubmission?['snapshotType'] == 'existing_record';
    final expanded = _expandedHistory.contains(report.id);
    final status = report.dismissReason == 'needs_correction'
        ? 'Needs correction'
        : reportReviewLabel(report);
    final color = report.status == 'verified'
        ? p.passable
        : report.reviewOpen
        ? p.onWarningContainer
        : p.onSurfaceVariant;
    final sameTime = reportTimesShareMinute(report);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                tr(
                  context,
                  original
                      ? (earlier ? 'Earlier saved report' : 'Original report')
                      : 'Follow-up',
                ),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: p.primary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tr(context, status),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            original
                ? reportRoadName(report)
                : tr(context, followupChangeLabel(report.conditionChange)),
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            report.description,
            maxLines: expanded ? null : 2,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.5,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 15,
                color: p.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${tr(context, sameTime ? 'Observed and submitted' : 'Observed')}: ${_time(report.observedAt)}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 1.5,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (!sameTime)
            Padding(
              padding: const EdgeInsets.only(left: 21, top: 3),
              child: Text(
                '${tr(context, 'Submitted')}: ${_time(report.createdAt)}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  height: 1.5,
                  color: p.onSurfaceVariant,
                ),
              ),
            ),
          if (report.isHistoricalFollowup &&
              ['pending', 'under_review'].contains(report.status)) ...[
            const SizedBox(height: 10),
            _info(
              'The road was reviewed separately. This observation still awaits its own review.',
            ),
          ],
          const SizedBox(height: 6),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey('followup-evidence-${report.id}'),
              initiallyExpanded: expanded,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4),
              iconColor: p.primary,
              collapsedIconColor: p.primary,
              onExpansionChanged: (value) => setState(() {
                if (value) {
                  _expandedHistory.add(report.id);
                } else {
                  _expandedHistory.remove(report.id);
                }
              }),
              title: Text(
                tr(
                  context,
                  original
                      ? 'View original evidence'
                      : 'View follow-up evidence',
                ),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.primary,
                ),
              ),
              children: [
                if (report.imageUrl?.trim().isNotEmpty == true) ...[
                  ReportPhotoThumbnail(
                    report: report,
                    width: double.infinity,
                    height: 160,
                    showExpandBadge: true,
                  ),
                  const SizedBox(height: 8),
                  if (report.photoSubmittedAt != null &&
                      report.photoSubmittedAt!
                              .difference(report.createdAt)
                              .inMinutes
                              .abs() >=
                          1)
                    Text(
                      '${tr(context, 'Photo submission time')}: ${_time(report.photoSubmittedAt)}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        height: 1.5,
                        color: p.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    tr(
                      context,
                      'A submission time does not certify when a photo was captured.',
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      height: 1.5,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                ],
                ReportReference(reportId: report.id),
                if (report.pointsAwarded != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${tr(context, report.rewardCorrection == null ? 'Trust change at review' : 'Original review award')}: ${report.pointsAwarded! > 0 ? '+' : ''}${report.pointsAwarded}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: p.onSurface,
                      ),
                    ),
                  ),
                if (report.rewardCorrection != null)
                  Text(
                    '${tr(context, 'Bonus reversal')}: -${report.rewardCorrection!['reversed'] ?? 0}. ${tr(context, 'False-submission penalty')}: -${report.rewardCorrection!['penalty'] ?? 0}.',
                    style: GoogleFonts.inter(fontSize: 11, color: p.onSurface),
                  ),
              ],
            ),
          ),
          if (report.hasAdminUpdates)
            ReportMessageThread(
              reportId: report.id,
              report: report,
              isAdmin: _context!.viewerIsAdmin,
            ),
        ],
      ),
    );
  }

  List<Widget> _form(bool available) {
    final p = AppPalette.of(context);
    final textStyle = GoogleFonts.inter(
      fontSize: 13,
      color: p.onSurface,
      height: 1.5,
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Text(
          tr(context, 'Add a condition update'),
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: p.onSurface,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
        child: Text(
          tr(
            context,
            'Share only what you can currently observe safely. Your original report stays unchanged.',
          ),
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.5,
            color: p.onSurfaceVariant,
          ),
        ),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading('What changed?', Icons.water_drop_outlined),
            DropdownButtonFormField<String>(
              key: ValueKey('followup-change:$_change'),
              initialValue: _change,
              hint: Text(
                tr(context, 'Choose what changed'),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: p.onSurfaceVariant,
                ),
              ),
              isExpanded: true,
              itemHeight: null,
              dropdownColor: p.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              menuMaxHeight: MediaQuery.sizeOf(context).height * .5,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.primary),
              decoration: _decoration('Choose what changed'),
              style: textStyle,
              items: const ['worsened', 'improved', 'cleared', 'unchanged']
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(
                        tr(context, followupChangeLabel(v)),
                        style: textStyle,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: available
                  ? (value) => setState(() {
                      _change = value;
                      if (value == 'cleared') _severity = null;
                    })
                  : null,
            ),
            if (_change != 'cleared') ...[
              const SizedBox(height: 14),
              Text(
                tr(context, 'Flood level you observe'),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: p.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 7),
              DropdownButtonFormField<String>(
                key: ValueKey('followup-severity:$_severity'),
                initialValue: _severity,
                hint: Text(
                  tr(context, 'Choose the flood level you observe'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: p.onSurfaceVariant,
                  ),
                ),
                isExpanded: true,
                itemHeight: null,
                dropdownColor: p.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.primary),
                style: textStyle,
                decoration: _decoration('Choose the flood level you observe'),
                items: const ['Low', 'Medium', 'High']
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(tr(context, v), style: textStyle),
                      ),
                    )
                    .toList(),
                onChanged: available
                    ? (value) => setState(() => _severity = value)
                    : null,
              ),
            ],
            const SizedBox(height: 14),
            Text(
              tr(context, 'Describe your observation'),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: p.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              key: const ValueKey('followup-description'),
              controller: _description,
              onChanged: (_) => setState(() {}),
              enabled: available,
              maxLength: 2000,
              minLines: 3,
              maxLines: 6,
              style: textStyle,
              decoration: _decoration('Describe what is different now.'),
            ),
          ],
        ),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(
              'When did you observe these conditions?',
              Icons.schedule_outlined,
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _observedAt == null
                    ? tr(
                        context,
                        'Observation time: now (recorded when you submit)',
                      )
                    : _time(_observedAt),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  color: p.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: available ? _chooseTime : null,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                  label: Text(
                    tr(context, 'Choose observation time'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: available
                      ? () => setState(() => _observedAt = null)
                      : null,
                  icon: Icon(
                    _observedAt == null ? Icons.check_circle : Icons.update,
                    size: 16,
                  ),
                  label: Text(
                    tr(context, 'Observed now'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading('Current photo', Icons.add_a_photo_outlined),
            Text(
              tr(
                context,
                'A new photo is optional. Your earlier photo stays with the original report.',
              ),
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.5,
                color: p.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_photo != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  _photo!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _photoConfirmed,
                onChanged: available
                    ? (value) => setState(() => _photoConfirmed = value == true)
                    : null,
                title: Text(
                  tr(
                    context,
                    'This photo shows the observation described in this update.',
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.5,
                    color: p.onSurface,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: available
                      ? () => setState(() {
                          _photo = null;
                          _photoReference = null;
                          _photoConfirmed = false;
                        })
                      : null,
                  child: Text(tr(context, 'Remove photo')),
                ),
              ),
            ],
            OutlinedButton.icon(
              onPressed: available ? _pickPhoto : null,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(
                tr(context, 'Attach a current photo (optional)'),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _urgent,
              onChanged: available ? (v) => setState(() => _urgent = v) : null,
              title: Text(
                tr(context, 'Request urgent admin review'),
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: p.onSurface,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  tr(
                    context,
                    'This flags the update for review. It does not confirm rescue dispatch.',
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 1.5,
                    color: p.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _info(
              'Respond only from a safe place. Do not enter floodwater.',
              warning: true,
            ),
          ],
        ),
      ),
      _info(
        'Submitting does not earn automatic points. An admin reviews each update; only one meaningful follow-up bonus is available per incident.',
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            tr(context, _error!),
            style: GoogleFonts.inter(fontSize: 12, height: 1.5, color: p.error),
          ),
        ),
      if (_saving || _processing)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(value: _processing ? null : _progress),
        ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: available ? _save : null,
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
        child: Text(
          tr(context, 'Submit follow-up'),
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: available ? _load : null,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: Text(tr(context, 'Refresh history')),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final available =
        !_saving && !_loading && !_processing && _loadError == null;
    return PopScope(
      canPop: !_saving && !_processing && (_allowLeave || !_hasDraft),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_allowLeave) _leave();
      },
      child: Scaffold(
        appBar: AppTopBar(
          title: 'Condition history',
          showBackButton: true,
          showProfile: false,
          showSettingsAction: false,
          onBackPressed: _leave,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_loadError != null)
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, _loadError!)),
                    TextButton(
                      onPressed: _saving || _accountChanged ? null : _load,
                      child: Text(tr(context, 'Refresh history')),
                    ),
                  ],
                ),
              ),
            if (_context != null) ...[
              _history(_context!.original, original: true),
              for (final update in _context!.updates) _history(update),
              if (!widget.readOnly && !_context!.canSubmit)
                _card(
                  Text(
                    tr(
                      context,
                      _context!.closedReason ??
                          'Only the original reporter can add a follow-up.',
                    ),
                  ),
                ),
              if (!widget.readOnly && _context!.canSubmit)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _form(available),
                ),
              if (widget.readOnly || !_context!.canSubmit)
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: available ? _load : null,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(tr(context, 'Refresh history')),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
