import 'admin_report_composer_ui.dart';
import '../models/user_report.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import 'report_workflow_ui.dart';
import 'package:flutter/material.dart';
import '../services/admin_report_service.dart';

Future<AdminActionResult?> showAdminReply(
  BuildContext context,
  String reportId,
) => showDialog<AdminActionResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => AdminReplyDialog(reportId: reportId),
);

class AdminReplyDialog extends StatefulWidget {
  final String reportId;
  final bool asSheet;
  final UserReport? report;
  final TextEditingController? controller;
  final Future<AdminActionResult> Function(String, Map<String, dynamic>)?
  perform;
  const AdminReplyDialog({
    super.key,
    required this.reportId,
    this.asSheet = false,
    this.report,
    this.perform,
    this.controller,
  });
  @override
  State<AdminReplyDialog> createState() => _AdminReplyDialogState();
}

class _AdminReplyDialogState extends State<AdminReplyDialog> {
  late final TextEditingController _message;
  @override
  void initState() {
    super.initState();
    _message = widget.controller ?? TextEditingController();
  }

  bool _saving = false;
  String? _error;

  Future<void> _useStarter(String text) async {
    final translated = tr(context, text);
    if (_message.text.trim().isNotEmpty && _message.text.trim() != translated) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(tr(context, 'Replace your draft?')),
          content: Text(
            tr(
              context,
              'This message starter will replace the text you have written.',
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
      if (replace != true || !mounted || _saving) return;
    }
    if (mounted && !_saving)
      setState(() {
        _message.text = translated;
        _message.selection = TextSelection.collapsed(offset: translated.length);
      });
  }

  @override
  void dispose() {
    if (widget.controller == null) _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_saving || _message.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await (widget.perform ?? AdminReportService.perform)(
        'reply',
        {'reportId': widget.reportId, 'message': _message.text.trim()},
      );
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The message save was not confirmed. Your text is kept here; retry to check.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: ReportActionDialog(
      fixedHeader: true,
      asSheet: widget.asSheet,
      title: 'Message the reporter',
      icon: Icons.chat_bubble_outline,
      reportId: widget.reportId,
      children: [
        if (widget.report != null && widget.report!.id == widget.reportId) ...[
          AdminReportContextCard(
            report: widget.report!,
            showReference: widget.asSheet,
          ),
          const SizedBox(height: 12),
        ],
        AdminReportEditorCard(
          controller: _message,
          title: 'Private admin update',
          hint: 'Write an acknowledgement or a factual update.',
          enabled: !_saving,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        ReportPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    color: AppPalette.of(context).primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(context, 'Message starters (optional)'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppPalette.of(context).onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  context,
                  'Tap one to fill your message, then edit it before sending.',
                ),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: AppPalette.of(context).onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final text in [
                'Your report has been received.',
                'We are reviewing the reported conditions.',
              ])
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _message.text.trim() == tr(context, text)
                        ? AppPalette.of(context).primary.withValues(alpha: .08)
                        : null,
                    side: BorderSide(
                      color: AppPalette.of(
                        context,
                      ).outlineVariant.withValues(alpha: .5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : () => _useStarter(text),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(context, text),
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ReportPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  context,
                  'Sending a message does not verify the report or change the road condition. Record a review decision separately.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppPalette.of(context).onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  'The reporter can read this in the app. Saving a message does not confirm push delivery or rescue dispatch.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppPalette.of(context).onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            tr(context, _error!),
            style: TextStyle(color: AppPalette.of(context).error),
          ),
        ],
      ],
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(tr(context, 'Cancel')),
        ),
        FilledButton(
          onPressed: _saving || _message.text.trim().isEmpty ? null : _send,
          child: Text(
            tr(context, _saving ? 'Confirming send...' : 'Send update'),
          ),
        ),
      ],
    ),
  );
}
