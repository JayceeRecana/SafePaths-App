import 'package:flutter/material.dart';
import '../services/communication_service.dart';
import '../config/app_environment.dart';

class CommunicationAdminDialog extends StatefulWidget {
  final String kind, id;
  final Future<Map<String, dynamic>> Function(String, String)? loadContext;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  saveAction;
  const CommunicationAdminDialog({
    super.key,
    required this.kind,
    required this.id,
    this.loadContext,
    this.saveAction,
  });
  @override
  State<CommunicationAdminDialog> createState() =>
      _CommunicationAdminDialogState();
}

class _CommunicationAdminDialogState extends State<CommunicationAdminDialog> {
  final _note = TextEditingController();
  Map<String, dynamic>? _context;
  String? _error;
  String _action = 'review', _outcome = 'recorded';
  bool _busy = false, _notify = false, _confirmed = false;
  bool get feedback => widget.kind == 'feedback';
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
      _busy = true;
      _error = null;
    });
    try {
      final value = await (widget.loadContext ?? CommunicationService.context)(
        widget.kind,
        widget.id,
      );
      if (mounted)
        setState(() {
          _context = value;
          _action = value['status'] == 'resolved'
              ? 'reopen'
              : value['status'] == 'new'
              ? 'review'
              : 'reply';
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The current record could not be loaded. Refresh to retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final loaded = _context;
    if (loaded == null) return;
    final note = _note.text.trim();
    if ((!feedback || _action == 'resolve') && note.length < 10 ||
        feedback && _action == 'reply' && note.isEmpty ||
        feedback && _action == 'resolve' && !_confirmed) {
      setState(
        () => _error =
            'Provide an accurate note and confirm the closure outcome when required.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await (widget.saveAction ?? CommunicationService.command)(
        feedback ? 'feedback-action' : 'broadcast-action',
        {
          (feedback ? 'feedbackId' : 'alertId'): widget.id,
          'contextToken': loaded['token'],
          'note': note,
          if (feedback) 'action': _action,
          if (feedback)
            'notify': _notify && AppEnvironment.communicationPushAllowed,
          if (feedback && _action == 'resolve') 'outcome': _outcome,
          if (feedback && _action == 'resolve') 'confirmed': _confirmed,
        },
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            (result['queuedCount'] as int) > 0
                ? 'Update saved in feedback history. Notification queued; phone receipt is unconfirmed.'
                : feedback
                ? 'Feedback update saved.'
                : 'Alert withdrawn. Already received notifications cannot be recalled.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _context;
    final choices = loaded?['status'] == 'resolved'
        ? {'reopen': 'Reopen for review'}
        : {
            'review': 'Mark under review',
            'reply': 'Save a reply',
            'resolve': 'Close feedback',
          };
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(feedback ? 'Review feedback' : 'Withdraw alert'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (loaded != null && feedback)
                  DropdownButtonFormField<String>(
                    itemHeight: null,
                    initialValue: _action,
                    key: ValueKey('action:$_action:${loaded['token']}'),
                    isExpanded: true,
                    items: choices.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _action = value!;
                            _confirmed = false;
                          }),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLines: 4,
                  maxLength: 2000,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: feedback
                        ? 'Factual update / closure note'
                        : 'Withdrawal reason (at least 10 characters)',
                  ),
                ),
                if (feedback && _action == 'reply')
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Acknowledgement'),
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _note.text =
                                    'Thank you. Your feedback has been received for review.',
                              ),
                      ),
                      ActionChip(
                        label: const Text('Under review'),
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _note.text =
                                    'Your feedback is under review. We will record the outcome here.',
                              ),
                      ),
                    ],
                  ),
                if (feedback && _action == 'resolve') ...[
                  DropdownButtonFormField<String>(
                    itemHeight: null,
                    initialValue: _outcome,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'recorded',
                        child: Text('Recorded; no fix claimed'),
                      ),
                      DropdownMenuItem(
                        value: 'addressed',
                        child: Text('Addressed; explain what changed'),
                      ),
                      DropdownMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicate; explain where handled'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _outcome = value!),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I checked this outcome and the note is accurate.',
                    ),
                    value: _confirmed,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _confirmed = value!),
                  ),
                ],
                if (feedback)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Queue a generic update notification'),
                    subtitle: Text(
                      loaded?['allowFollowUp'] == true
                          ? 'The reply remains available in private history.'
                          : 'No follow-up permission: no optional notification will be sent.',
                    ),
                    value: _notify,
                    onChanged:
                        _busy ||
                            loaded?['allowFollowUp'] != true ||
                            loaded?['owned'] != true ||
                            !AppEnvironment.communicationPushAllowed
                        ? null
                        : (value) => setState(() => _notify = value!),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Refresh'),
          ),
          FilledButton(
            onPressed: _busy || loaded == null ? null : _save,
            child: Text(feedback ? 'Save update' : 'Withdraw'),
          ),
        ],
      ),
    );
  }
}
