import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import 'report_workflow_ui.dart';
import 'package:flutter/material.dart';
import '../services/admin_report_service.dart';

Future<AdminActionResult?> showAdminDismiss(
  BuildContext context,
  String reportId, {
  bool asSheet = false,
}) => asSheet
    ? showModalBottomSheet<AdminActionResult>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => AdminDismissDialog(reportId: reportId, asSheet: true),
      )
    : showDialog<AdminActionResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AdminDismissDialog(reportId: reportId),
      );

class AdminDismissDialog extends StatefulWidget {
  final String reportId;
  final bool asSheet;
  final Future<Map<String, dynamic>> Function()? loadContext;
  final Future<AdminActionResult> Function(String, Map<String, dynamic>)?
  perform;
  const AdminDismissDialog({
    super.key,
    required this.reportId,
    this.asSheet = false,
    this.loadContext,
    this.perform,
  });
  @override
  State<AdminDismissDialog> createState() => _AdminDismissDialogState();
}

class _AdminDismissDialogState extends State<AdminDismissDialog> {
  Map<String, dynamic>? _context;
  String _reason = 'duplicate_resolved';
  bool _loading = true,
      _saving = false,
      _confirmSos = false,
      _confirmFalse = false;
  String? _error;
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.asSheet) _reason = '';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _context = null;
      _error = null;
      _confirmSos = false;
      _confirmFalse = false;
    });
    try {
      final latest =
          await (widget.loadContext?.call() ??
              AdminReportService.context(reportId: widget.reportId));
      if (mounted) setState(() => _context = latest);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'The latest report could not be loaded. Retry.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _reason.isEmpty ||
        _context == null ||
        (_context?['workflowVersion'] == 2 && _note.text.trim().length < 10))
      return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result =
          await (widget.perform ?? AdminReportService.perform)('dismiss', {
            'reportId': widget.reportId,
            'contextToken': _context!['token'],
            'reason': _reason,
            'confirmEmergency': _confirmSos,
            'confirmedFalseReport': _confirmFalse,
            'note': _note.text.trim(),
          });
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Dismissal was not confirmed. Retry, or refresh if new information arrived.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _context?['report'] as Map?,
        sos = report?['isEmergency'] == true;
    final followup = report?['reportType'] == 'followup';
    return PopScope(
      canPop: !_saving,
      child: ReportActionDialog(
        asSheet: widget.asSheet,
        title: sos
            ? 'Review SOS dismissal'
            : widget.asSheet
            ? 'Why is it not verified?'
            : 'Complete without verification',
        icon: Icons.fact_check_outlined,
        reportId: widget.reportId,
        children: [
          if (_context?['selfReview'] == true)
            Text(
              tr(
                context,
                'Another administrator must review your own report or follow-up.',
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (report != null) ...[
            ReportPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${report['title']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${report['description']}',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            tr(context, 'Review outcome'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            itemHeight: null,
            initialValue: _reason.isEmpty ? null : _reason,
            hint: Text(tr(context, 'Choose a reason')),
            items: [
              if (_context?['workflowVersion'] == 2)
                DropdownMenuItem(
                  value: 'unable_to_verify',
                  child: Text(tr(context, 'Unable to verify (no penalty)')),
                ),
              if (followup)
                DropdownMenuItem(
                  value: 'needs_correction',
                  child: Text(
                    tr(
                      context,
                      'Wrong attachment / needs clarification (no penalty)',
                    ),
                  ),
                ),
              DropdownMenuItem(
                value: 'duplicate_resolved',
                child: Text(tr(context, 'Duplicate submission')),
              ),
              DropdownMenuItem(
                value: 'spam_false',
                child: Text(tr(context, 'Confirmed false / spam')),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null)
                      setState(() {
                        _reason = value;
                        _confirmFalse = false;
                      });
                  },
          ),
          const SizedBox(height: 12),
          Text(
            _reason.isEmpty
                ? tr(
                    context,
                    'Choose a reason to see its effect on trust points.',
                  )
                : _reason == 'spam_false'
                ? tr(
                    context,
                    followup
                        ? 'This deducts up to 5 trust points. The original report keeps its outcome.'
                        : 'This deducts up to 15 trust points.',
                  )
                : tr(context, 'No trust points will be deducted.'),
          ),
          const SizedBox(height: 10),
          ReportPanel(
            tint: AppPalette.of(context).warning.withValues(alpha: .08),
            child: Text(
              tr(
                context,
                'Receding floodwater alone does not make an earlier report false.',
              ),
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),
          if (_reason == 'spam_false')
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              value: _confirmFalse,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _confirmFalse = value == true),
              title: Text(
                tr(
                  context,
                  'I reviewed evidence confirming this report is false or spam.',
                ),
              ),
            ),
          if (_context?['workflowVersion'] == 2 ||
              followup &&
                  const [
                    'spam_false',
                    'needs_correction',
                  ].contains(_reason)) ...[
            Text(
              tr(
                context,
                _reason == 'needs_correction'
                    ? 'Explain what the resident needs to clarify'
                    : 'Explain the decision to the resident',
              ),
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              enabled: !_saving,
              maxLength: 1000,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: tr(context, 'Write your explanation here...'),
                hintMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _confirmFalse = false),
            ),
          ],
          if (sos)
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              value: _confirmSos,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _confirmSos = value == true),
              title: Text(
                tr(
                  context,
                  'I acknowledge removing this report from the SOS review queue. This does not record rescue dispatch or completion.',
                ),
              ),
            ),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _saving ? null : _load,
              child: Text(tr(context, 'Refresh latest report')),
            ),
          ],
        ],
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(tr(context, 'Cancel')),
          ),
          FilledButton(
            onPressed:
                _loading ||
                    _reason.isEmpty ||
                    _saving ||
                    _context == null ||
                    _context?['selfReview'] == true ||
                    (sos && !_confirmSos) ||
                    (_reason == 'spam_false' && !_confirmFalse) ||
                    (_context?['workflowVersion'] == 2 &&
                        _note.text.trim().length < 10) ||
                    (followup &&
                        const [
                          'spam_false',
                          'needs_correction',
                        ].contains(_reason) &&
                        _note.text.trim().length < 10)
                ? null
                : _save,
            child: Text(
              _saving
                  ? 'Confirming save…'
                  : tr(
                      context,
                      widget.asSheet ? 'Save decision' : 'Save dismissal',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
