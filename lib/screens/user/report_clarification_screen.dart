import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_report.dart';
import '../../widgets/report_submission_preview.dart';
import 'package:flutter/services.dart';
import '../../widgets/report_workflow_ui.dart';
import '../../theme/app_palette.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/formatters.dart';
import '../../services/report_clarification_service.dart';
import '../../services/report_photo_uploader.dart';
import '../../utils/report_image.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/safe_image.dart';
import '../../widgets/report_photo_attachment_card.dart';

class ReportClarificationScreen extends StatefulWidget {
  final String reportId;
  final UserReport? report;
  final bool isAdmin;
  final Stream<Map<String, dynamic>?>? reportChanges;
  final Future<Map<String, dynamic>> Function()? loadContext;
  final Future<void> Function(Map<String, dynamic>)? send;
  const ReportClarificationScreen({
    super.key,
    required this.reportId,
    this.report,
    this.isAdmin = false,
    this.reportChanges,
    this.loadContext,
    this.send,
  });
  @override
  State<ReportClarificationScreen> createState() =>
      _ReportClarificationScreenState();
}

class _ReportClarificationScreenState extends State<ReportClarificationScreen> {
  final _message = TextEditingController(), _uploader = ReportPhotoUploader();
  Map<String, dynamic>? _data;
  Uint8List? _photo;
  String? _photoReference, _error, _uid;
  DateTime? _photoTime;
  String? _draftRequestId, _draftQuestion;
  bool _allowLeave = false, _accountChanged = false;
  bool get _hasDraft => _message.text.trim().isNotEmpty || _photo != null;
  bool get _questionChanged =>
      _hasDraft &&
      _data != null &&
      _draftRequestId != null &&
      _draftRequestId != _data!['requestId'];

  bool get _draftBlocked =>
      _questionChanged ||
      _hasDraft && _data != null && _data!['canReply'] != true;

  Future<bool> _confirmDiscard({bool newQuestion = false}) async {
    if (!_hasDraft) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(
              tr(
                context,
                newQuestion
                    ? 'Start a new reply?'
                    : 'Discard your unsent reply?',
              ),
            ),
            content: Text(
              tr(
                context,
                newQuestion
                    ? 'Copy the previous draft first if you need it. Starting a new reply clears its text and attachment from this screen.'
                    : 'Your text and attachment have not been confirmed as saved. Keep editing to preserve this draft.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(tr(context, 'Keep editing')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(
                  tr(
                    context,
                    newQuestion ? 'Start new reply' : 'Discard draft',
                  ),
                ),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _startNewReply() async {
    final request = _data?['requestId'];
    if (_busy || _data?['canReply'] != true) return;
    if (!await _confirmDiscard(newQuestion: true) ||
        !mounted ||
        _busy ||
        _data?['canReply'] != true ||
        _data?['requestId'] != request)
      return;
    setState(() {
      _message.clear();
      _photo = null;
      _photoReference = null;
      _photoTime = null;
      _confirmed = false;
      _draftRequestId = _data!['requestId'] as String?;
      _draftQuestion = _data!['question'] as String?;
      _error = null;
    });
  }

  bool _confirmed = false, _loading = true, _busy = false, _picking = false;
  StreamSubscription<User?>? _auth;
  StreamSubscription<Map<String, dynamic>?>? _reportWatch;
  Object? _reportRevision;
  bool _refreshPending = false;

  void _reportChanged(Map<String, dynamic>? report) {
    if (!mounted || _accountChanged) return;
    if (report == null ||
        widget.loadContext == null &&
            !widget.isAdmin &&
            report['userId'] != _uid) {
      _generation++;
      _refreshPending = false;
      _reportRevision = ('unavailable', null, null);
      setState(() {
        _data = null;
        _message.clear();
        _photo = null;
        _photoReference = null;
        _loading = false;
        _busy = false;
        _picking = false;
        _error = 'This report is unavailable. Return to your report history.';
      });
      return;
    }
    final revision = (
      report['clarificationRequestId'],
      report['clarificationRepliedAt'],
      report['status'],
    );
    final changed = _reportRevision != null && revision != _reportRevision;
    _reportRevision = revision;
    if (changed ||
        _data != null &&
            report['clarificationRequestId'] != _data!['requestId']) {
      _refreshPending = true;
      _refreshIfReady();
    }
  }

  void _refreshIfReady() {
    if (!mounted || !_refreshPending || _loading || _busy || _picking) return;
    _refreshPending = false;
    _load();
  }

  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.loadContext == null) {
      _uid = FirebaseAuth.instance.currentUser?.uid;
      _auth = FirebaseAuth.instance.userChanges().listen((user) {
        if (user?.uid != _uid && mounted) {
          _generation++;
          _accountChanged = true;
          _refreshPending = false;
          _reportWatch?.cancel();
          setState(() {
            _loading = false;
            _busy = false;
            _picking = false;
            _data = null;
            _photo = null;
            _photoReference = null;
            _message.clear();
            _error = 'Account changed. Reopen your report.';
          });
        }
      });
    }
    final changes =
        widget.reportChanges ??
        (widget.loadContext == null
            ? FirebaseFirestore.instance
                  .collection('reports')
                  .doc(widget.reportId)
                  .snapshots(includeMetadataChanges: true)
                  .where(
                    (snapshot) =>
                        snapshot.exists || !snapshot.metadata.isFromCache,
                  )
                  .map((snapshot) => snapshot.exists ? snapshot.data() : null)
            : null);
    _reportWatch = changes?.listen(
      _reportChanged,
      onError: (Object _) {
        if (mounted && !_accountChanged)
          setState(
            () => _error =
                'Live report changes are unavailable. Refresh latest details before replying.',
          );
      },
    );
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _auth?.cancel();
    _reportWatch?.cancel();
    _message.dispose();
    _uploader.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_accountChanged) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _data = null;
      _error = null;
    });
    try {
      final data =
          await (widget.loadContext?.call() ??
              ReportClarificationService.load(widget.reportId));
      if (mounted && generation == _generation)
        setState(() {
          if (!_hasDraft || _draftRequestId == null) {
            _draftRequestId = data['requestId'] as String?;
            _draftQuestion = data['question'] as String?;
          }
          final response = data['response'];
          if (data['requestId'] == _draftRequestId &&
              response is Map &&
              response['message'] == _message.text.trim() &&
              (_photo == null || response['imageUrl'] == _photoReference)) {
            _message.clear();
            _photo = null;
            _photoReference = null;
            _photoTime = null;
            _confirmed = false;
          }
          _data = data;
        });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(
          () => _error =
              'Could not load this clarification. Your draft is preserved. Retry.',
        );
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
      _refreshIfReady();
    }
  }

  Future<void> _pick() async {
    final generation = _generation;
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      if (await file.length() > maxReportPhotoBytes)
        throw const FormatException();
      final bytes = await compute(prepareReportImage, await file.readAsBytes());
      if (mounted && generation == _generation)
        setState(() {
          _photo = bytes;
          _photoReference = null;
          _photoTime = null;
          _confirmed = false;
        });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(
          () => _error =
              'Could not prepare the photo. Choose a JPG or PNG up to 10 MB.',
        );
    } finally {
      if (mounted && generation == _generation)
        setState(() => _picking = false);
      _refreshIfReady();
    }
  }

  String? get _draftProblem => clarificationDraftProblem(
    text: _message.text,
    now: DateTime.now(),
    hasPhoto: _photo != null,
    photoConfirmed: _confirmed,
    photoObservedAt: _photoTime,
  );

  Future<void> _chooseTime() async {
    final generation = _generation;
    if (_accountChanged || _busy || _picking) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _photoTime ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (!mounted ||
        generation != _generation ||
        _accountChanged ||
        date == null)
      return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_photoTime ?? now),
      builder: twelveHourPickerBuilder,
    );
    if (mounted &&
        generation == _generation &&
        !_accountChanged &&
        time != null)
      setState(() {
        _photoTime = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        _confirmed = false;
      });
  }

  Future<void> _save() async {
    if (_busy ||
        _accountChanged ||
        _picking ||
        _questionChanged ||
        _draftRequestId != _data?['requestId'] ||
        _data?['canReply'] != true)
      return;
    final problem = _draftProblem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_photo != null && _photoReference == null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) throw StateError('Account changed.');
        final reference = await _uploader.upload(
          'clarification-${_data!['requestId']}',
          uid,
          _photo!,
          (_) {},
        );
        if (!mounted || generation != _generation || _accountChanged) return;
        _photoReference = reference;
      }
      if (!mounted || generation != _generation || _accountChanged) return;
      await (widget.send ?? ReportClarificationService.reply)({
        'reportId': widget.reportId,
        'clarificationRequestId': _data!['requestId'],
        'message': _message.text.trim(),
        if (_photoReference != null) ...{
          'imageUrl': _photoReference,
          'photoObservedAt': _photoTime!.toUtc().toIso8601String(),
          'photoMatchesObservation': true,
        },
      });
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Reply saved. Your report is back in the review queue.',
              ),
            ),
          ),
        );
        _allowLeave = true;
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted && generation == _generation)
        setState(
          () => _error =
              'Reply not confirmed. Keep your draft and retry, or refresh the request.',
        );
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
      _refreshIfReady();
    }
  }

  @override
  Widget build(BuildContext context) {
    final response = _data?['response'] as Map?;
    final p = AppPalette.of(context);
    String? timeOf(dynamic value) {
      final time = value is String ? DateTime.tryParse(value) : null;
      return time == null ? null : localizedDateTime(context, time);
    }

    return PopScope(
      canPop: !_busy && (_allowLeave || !_hasDraft),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_allowLeave) _leave();
      },
      child: Scaffold(
        appBar: AppTopBar(
          title: tr(context, 'Report clarification'),
          showBackButton: true,
          showProfile: false,
          showSettingsAction: false,
          onBackPressed: _leave,
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_data != null) ...[
                if (widget.report != null &&
                    widget.report!.id == widget.reportId)
                  ReportSubmissionPreview(report: widget.report!)
                else
                  ReportPanel(
                    child: ReportReference(reportId: widget.reportId),
                  ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: p.primary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        tr(
                          context,
                          'Private to the reporter and authorized barangay admins.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: p.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ReportConversationCard(
                  title: widget.isAdmin
                      ? 'Question to the resident'
                      : 'The barangay asked',
                  message: _data!['question'] as String? ?? '',
                  time: timeOf(_data!['createdAt']),
                ),
                const SizedBox(height: 12),
                if (response != null) ...[
                  ReportConversationCard(
                    title: 'Resident reply',
                    message: response['message'] as String? ?? '',
                    resident: true,
                    time: timeOf(response['repliedAt']),
                    attachment: response['imageUrl'] is String
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SafeImage(
                                  imageUrl: response['imageUrl'],
                                  height: 200,
                                ),
                              ),
                              if (timeOf(response['photoObservedAt']) != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '${tr(context, 'Photo observation time')}: ${timeOf(response['photoObservedAt'])}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                            ],
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  ReportPanel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.fact_check_outlined,
                          color: p.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            tr(
                              context,
                              widget.isAdmin
                                  ? 'Read this reply before recording your review decision.'
                                  : 'Your reply is saved. Follow the report updates for the latest review status.',
                            ),
                            style: const TextStyle(fontSize: 12, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!widget.isAdmin &&
                    _data!['canReply'] != true &&
                    response == null &&
                    !_draftBlocked) ...[
                  ReportPanel(
                    tint: p.warningContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(
                            context,
                            'This question no longer accepts replies',
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: p.onWarningContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            context,
                            'Return to your report updates to check the latest review status.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: p.onWarningContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _leave,
                          icon: const Icon(Icons.arrow_back, size: 17),
                          label: Text(tr(context, 'Back to report updates')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_draftBlocked) ...[
                  ReportPanel(
                    tint: p.warningContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(
                            context,
                            _questionChanged
                                ? 'The barangay question changed'
                                : 'This question no longer accepts replies',
                          ),
                          style: TextStyle(
                            color: p.onWarningContainer,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            context,
                            _questionChanged
                                ? 'Your draft belongs to the previous question. Copy it before starting a reply to the new question.'
                                : 'Your draft was kept on this screen. Copy it if you need it.',
                          ),
                          style: TextStyle(
                            color: p.onWarningContainer,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        if (_draftQuestion != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _draftQuestion!,
                            style: TextStyle(color: p.onWarningContainer),
                          ),
                        ],
                        const SizedBox(height: 10),
                        SelectableText(
                          _message.text,
                          style: TextStyle(
                            color: p.onWarningContainer,
                            fontSize: 14,
                          ),
                        ),
                        if (_photo != null) ...[
                          const SizedBox(height: 10),
                          Image.memory(_photo!, height: 140),
                        ],
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _message.text.isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: _message.text),
                                  );
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          tr(context, 'Draft text copied.'),
                                        ),
                                      ),
                                    );
                                },
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: Text(tr(context, 'Copy draft text')),
                        ),
                        if (_data!['canReply'] == true)
                          FilledButton(
                            onPressed: _startNewReply,
                            child: Text(tr(context, 'Start a new reply')),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      onPressed: _leave,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: Text(tr(context, 'Back to report review')),
                    ),
                  ),
                if (_data!['canReply'] == true &&
                    !_questionChanged &&
                    !widget.isAdmin) ...[
                  ReportPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(context, 'Your reply'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: p.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(
                            context,
                            'Answer the question about your original report. Your original photo and time are kept.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: p.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _message,
                          maxLength: 2000,
                          minLines: 3,
                          maxLines: 8,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: tr(context, 'Write your reply here...'),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const SizedBox(height: 12),
                        ReportPhotoAttachmentCard(
                          embedded: true,
                          label: 'Photo evidence (optional)',
                          sourceHint: 'Choose from gallery',
                          processing: _picking,
                          preview: _photo == null ? null : MemoryImage(_photo!),
                          onPick: _picking || _busy ? null : _pick,
                          onRemove: _busy || _picking
                              ? null
                              : () => setState(() {
                                  _photo = null;
                                  _photoReference = null;
                                  _photoTime = null;
                                  _confirmed = false;
                                }),
                        ),
                        if (_photo != null) ...[
                          TextButton.icon(
                            onPressed: _chooseTime,
                            icon: const Icon(Icons.schedule),
                            label: Text(
                              _photoTime == null
                                  ? tr(context, 'When was this photo observed?')
                                  : localizedDateTime(context, _photoTime!),
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _confirmed,
                            onChanged: (v) =>
                                setState(() => _confirmed = v == true),
                            title: Text(
                              tr(
                                context,
                                'This photo supports the original observation at the time selected.',
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: p.warning.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 18,
                                color: p.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr(
                                    context,
                                    'Respond only from a safe place. Do not enter floodwater.',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: p.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_draftProblem != null) ...[
                          Text(
                            tr(context, _draftProblem!),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: p.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        FilledButton(
                          onPressed: _picking || _draftProblem != null
                              ? null
                              : _save,
                          child: Text(
                            tr(
                              context,
                              _busy ? 'Saving...' : 'Send clarification',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              if (_error != null) ...[
                Text(
                  tr(context, _error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _busy || _picking ? null : _load,
                  child: Text(tr(context, 'Refresh latest details')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
