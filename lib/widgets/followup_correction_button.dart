import 'package:flutter/material.dart';
import '../config/app_environment.dart';
import '../l10n/app_strings.dart';
import '../models/user_report.dart';
import '../services/admin_report_service.dart';

class FollowupCorrectionButton extends StatelessWidget {
  final UserReport report;
  final VoidCallback? onSaved;
  const FollowupCorrectionButton({
    super.key,
    required this.report,
    this.onSaved,
  });
  @override
  Widget build(BuildContext context) {
    if (!AppEnvironment.sparkFollowupsEnabled ||
        !report.isFollowup ||
        report.status != 'verified' ||
        report.rewardCorrection != null)
      return const SizedBox.shrink();
    return TextButton.icon(
      icon: const Icon(Icons.history_edu_outlined),
      label: Text(tr(context, 'Correct this follow-up review')),
      onPressed: () async {
        final result = await showDialog<AdminActionResult>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FollowupCorrectionDialog(reportId: report.id),
        );
        if (result != null && context.mounted) {
          onSaved?.call();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.confirmation)));
        }
      },
    );
  }
}

class FollowupCorrectionDialog extends StatefulWidget {
  final String reportId;
  final Future<Map<String, dynamic>> Function()? loadContext;
  final Future<AdminActionResult> Function(String, Map<String, dynamic>)?
  perform;
  const FollowupCorrectionDialog({
    super.key,
    required this.reportId,
    this.loadContext,
    this.perform,
  });
  @override
  State<FollowupCorrectionDialog> createState() =>
      _FollowupCorrectionDialogState();
}

class _FollowupCorrectionDialogState extends State<FollowupCorrectionDialog> {
  final _note = TextEditingController();
  Map<String, dynamic>? _context;
  String? _reason, _error;
  bool _confirmed = false, _saving = false, _loading = true;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _context = null;
      _confirmed = false;
      _error = null;
    });
    try {
      final value =
          await (widget.loadContext?.call() ??
              AdminReportService.context(reportId: widget.reportId));
      if (mounted) setState(() => _context = value);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The current review could not be loaded. Retry before correcting it.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_context == null ||
        _reason == null ||
        _saving ||
        _note.text.trim().length < 10 ||
        _reason == 'confirmed_false' && !_confirmed)
      return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await (widget.perform ?? AdminReportService.perform)(
        'correct_followup',
        {
          'reportId': widget.reportId,
          'contextToken': _context!['token'],
          'reason': _reason,
          'note': _note.text.trim(),
          'confirmedFalseReport': _confirmed,
        },
      );
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The correction was not confirmed. Keep the reason and retry, or refresh the latest review.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(tr(context, 'Correct follow-up review')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_context?['selfReview'] == true)
            Text(
              tr(
                context,
                'Another administrator must review your own report or follow-up.',
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Text(
            tr(
              context,
              'This corrects only the follow-up. The original report keeps its outcome and reward. The road will require another current check.',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            itemHeight: null,
            hint: Text(tr(context, 'Choose why the review is being corrected')),
            items: [
              DropdownMenuItem(
                value: 'mistaken_approval',
                child: Text(
                  tr(context, 'Mistaken approval: reverse the bonus only'),
                ),
              ),
              DropdownMenuItem(
                value: 'confirmed_false',
                child: Text(
                  tr(
                    context,
                    'Confirmed false submission: reverse bonus and apply up to -5',
                  ),
                ),
              ),
            ],
            onChanged: _saving || _loading || _context == null
                ? null
                : (value) => setState(() {
                    _reason = value;
                    _confirmed = false;
                  }),
          ),
          TextField(
            controller: _note,
            enabled: !_saving,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: tr(
                context,
                'Correction reason and supporting evidence',
              ),
            ),
            onChanged: (_) => setState(() => _confirmed = false),
          ),
          if (_reason == 'confirmed_false')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _confirmed = value == true),
              title: Text(
                tr(
                  context,
                  'I reviewed evidence supporting a false or misleading submission. Unclear evidence alone is not misconduct.',
                ),
              ),
            ),
          if (_error != null) ...[
            Text(
              tr(context, _error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _saving ? null : _load,
              child: Text(tr(context, 'Refresh latest details')),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(tr(context, 'Cancel')),
        ),
        FilledButton(
          onPressed:
              _saving ||
                  _loading ||
                  _context == null ||
                  _context?['selfReview'] == true ||
                  _reason == null ||
                  _note.text.trim().length < 10 ||
                  _reason == 'confirmed_false' && !_confirmed
              ? null
              : _save,
          child: Text(tr(context, 'Save correction')),
        ),
      ],
    ),
  );
}
