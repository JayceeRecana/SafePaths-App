import 'admin_report_composer_ui.dart';
import '../theme/app_palette.dart';
import '../models/user_report.dart';
import 'report_workflow_ui.dart';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/admin_report_service.dart';

Future<AdminActionResult?> showAdminClarification(
  BuildContext context,
  String reportId,
) => showModalBottomSheet<AdminActionResult>(
  context: context,
  isScrollControlled: true,
  isDismissible: false,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  builder: (_) => AdminClarificationDialog(reportId: reportId, asSheet: true),
);

class AdminClarificationDialog extends StatefulWidget {
  final String reportId;
  final bool asSheet;
  final Future<Map<String, dynamic>> Function()? loadContext;
  const AdminClarificationDialog({
    super.key,
    required this.reportId,
    this.asSheet = false,
    this.loadContext,
  });
  @override
  State<AdminClarificationDialog> createState() =>
      _AdminClarificationDialogState();
}

class _AdminClarificationDialogState extends State<AdminClarificationDialog> {
  final _note = TextEditingController();
  Map<String, dynamic>? _context;
  bool _busy = false, _loading = true;
  String? _error;
  int? _preset;
  bool _allowLeave = false, _confirmingLeave = false;
  Future<void> _leave() async {
    if (_busy || _confirmingLeave) return;
    if (_note.text.trim().isNotEmpty) {
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
      if (discard != true || !mounted || _busy) return;
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
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _choosePreset(int index) async {
    const questions = [
      'When was this photo taken? Please confirm the observation time.',
      'Which side of the road or intersection is shown in your photo?',
      'If you can safely see this road now, is there still water? Do not go outside or enter floodwater to check.',
    ];
    if (_busy) return;
    final replacement = index == 3 ? _note.text : tr(context, questions[index]);
    if (index != 3 &&
        _note.text.trim().isNotEmpty &&
        _note.text.trim() != replacement) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(tr(context, 'Replace your draft?')),
          content: Text(
            tr(
              context,
              'The selected question will replace the text you have written.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(tr(context, 'Keep editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(tr(context, 'Replace text')),
            ),
          ],
        ),
      );
      if (replace != true || !mounted || _busy) return;
    }
    setState(() {
      _preset = index;
      if (index != 3) _note.text = replacement;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _context = null;
      _error = null;
    });
    try {
      final data =
          await (widget.loadContext?.call() ??
              AdminReportService.context(reportId: widget.reportId));
      if (!mounted) return;
      setState(() {
        if (data['workflowVersion'] != 2) {
          _error =
              'Clarification is not available on this backend yet. No request was sent.';
        } else {
          _context = data;
        }
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not load the latest report. Retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _context == null || _note.text.trim().length < 10) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await AdminReportService.perform('request_clarification', {
        'reportId': widget.reportId,
        'contextToken': _context!['token'],
        'note': _note.text.trim(),
      });
      if (mounted) {
        _allowLeave = true;
        Navigator.pop(context, result);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Request not confirmed. Your explanation is preserved. Retry or refresh the report.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  UserReport? get _report {
    final data = _context?['report'];
    if (data is! Map) return null;
    try {
      return UserReport.fromJson({
        ...Map<String, dynamic>.from(data),
        'id': widget.reportId,
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && (_allowLeave || _note.text.trim().isEmpty),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_allowLeave) _leave();
    },
    child: ReportActionDialog(
      fixedHeader: true,
      asSheet: widget.asSheet,
      title: 'Ask the resident',
      icon: Icons.question_answer_outlined,
      reportId: widget.reportId,
      children: [
        if (_report != null) ...[
          AdminReportContextCard(
            report: _report!,
            showReference: widget.asSheet,
          ),
          const SizedBox(height: 16),
        ],
        Text(
          tr(context, 'Choose a question'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ReportPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
                Semantics(
                  selected: _preset == i,
                  child: InkWell(
                    onTap: _busy ? null : () => _choosePreset(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _preset == i
                            ? AppPalette.of(context).warningContainer
                            : null,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(i == 0 ? 20 : 0),
                          bottom: Radius.circular(i == 3 ? 20 : 0),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr(
                                context,
                                const [
                                  'When was the photo taken?',
                                  'Which side of the road is this?',
                                  'Is there still water now?',
                                  'Write my own question',
                                ][i],
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: _preset == i
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _preset == i
                                    ? AppPalette.of(context).onWarningContainer
                                    : AppPalette.of(context).onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _preset == i
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: _preset == i
                                ? AppPalette.of(context).onWarningContainer
                                : AppPalette.of(context).onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading) const LinearProgressIndicator(),
        AdminReportEditorCard(
          controller: _note,
          title: 'Message to the resident',
          hint: 'What do you need to clarify?',
          question: true,
          enabled: !_busy,
          onChanged: (_) => setState(() => _preset = 3),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppPalette.of(context).warningContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 16,
                color: AppPalette.of(context).onWarningContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    context,
                    'Ask only for information they can provide safely.',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: AppPalette.of(context).onWarningContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Text(
            tr(context, _error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_error != null)
          TextButton(
            onPressed: _busy ? null : _load,
            child: Text(tr(context, 'Refresh latest details')),
          ),
      ],
      actions: [
        TextButton(
          onPressed: _busy ? null : _leave,
          child: Text(tr(context, 'Cancel')),
        ),
        FilledButton(
          onPressed:
              _busy ||
                  _loading ||
                  _context == null ||
                  _context?['selfReview'] == true ||
                  _note.text.trim().length < 10
              ? null
              : _save,
          child: Text(tr(context, _busy ? 'Saving...' : 'Send question')),
        ),
      ],
    ),
  );
}
