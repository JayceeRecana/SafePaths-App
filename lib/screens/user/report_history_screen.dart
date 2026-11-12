import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/report_history_card.dart';
import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';
import '../../services/report_history.dart';
import '../../widgets/report_history_controls.dart';
import '../../widgets/report_workflow_ui.dart';

class ReportHistoryScreen extends StatefulWidget {
  final String? userId;
  final bool embedded;
  final String? Function()? currentAccount;
  final Stream<String?>? accountChanges;
  final ReportHistory Function(String)? createHistory;
  final Future<void> Function(UserReport, String, String)? saveEdit;
  const ReportHistoryScreen({
    super.key,
    this.userId,
    this.embedded = false,
    this.currentAccount,
    this.accountChanges,
    this.createHistory,
    this.saveEdit,
  });

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  String? _userId;
  ReportHistory? _history;
  Listenable? _updates;
  bool _ownHistory = true;
  String? _accountError;
  String? _viewer;
  int _generation = 0;
  bool _accountChanged = false;
  StreamSubscription<String?>? _auth;
  BuildContext? _editContext;
  String? _currentAccount() {
    if (widget.currentAccount != null) return widget.currentAccount!();
    final user = FirebaseAuth.instance.currentUser;
    return user != null && user.emailVerified && !user.isAnonymous
        ? user.uid
        : null;
  }

  bool get _sameAccount =>
      !_accountChanged && _viewer != null && _currentAccount() == _viewer;

  @override
  void initState() {
    super.initState();
    _viewer = _currentAccount();
    _auth =
        (widget.accountChanges ??
                FirebaseAuth.instance.userChanges().map(
                  (user) =>
                      user != null && user.emailVerified && !user.isAnonymous
                      ? user.uid
                      : null,
                ))
            .listen((uid) {
              if (mounted && !_accountChanged && uid != _viewer) {
                final edit = _editContext;
                _editContext = null;
                if (edit != null && edit.mounted) Navigator.pop(edit);
                _generation++;
                _history?.dispose();
                setState(() {
                  _accountChanged = true;
                  _history = null;
                  _updates = null;
                  _userId = null;
                  _accountError =
                      'Account changed. Reopen report history from your account.';
                });
              }
            });
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!_sameAccount) {
      if (mounted)
        setState(
          () => _accountError =
              'Account changed. Reopen report history from your account.',
        );
      return;
    }
    final generation = ++_generation;
    try {
      final uid = _viewer!;
      final history =
          widget.createHistory?.call(widget.userId ?? uid) ??
          AppStateService.instance.createReportHistory(
            userId: widget.userId ?? uid,
          );
      _history?.dispose();
      setState(() {
        _userId = widget.userId ?? uid;
        _ownHistory = _userId == uid;
        _history = history;
        _updates = Listenable.merge([AppStateService.instance, history]);
        _accountError = null;
      });
      await history.refresh();
    } catch (_) {
      if (mounted && generation == _generation && _sameAccount) {
        setState(
          () => _accountError =
              'History is unavailable. Check your account and retry.',
        );
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_auth?.cancel());
    _history?.dispose();
    super.dispose();
  }

  Widget _historyLayout(Widget child) => Column(
    children: [
      if (_history!.loading ||
          _history!.error != null ||
          _history!.page.fromCache ||
          _history!.pageNumber > 1 ||
          _history!.page.next != null)
        ReportHistoryControls(history: _history!, showRefresh: false),
      Expanded(child: child),
    ],
  );

  Widget _refreshAction(BuildContext context) {
    final history = _history;
    if (history == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: history,
      builder: (context, _) => Tooltip(
        message: tr(context, 'Refresh history'),
        child: TextButton.icon(
          onPressed: _sameAccount && !history.loading ? history.refresh : null,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(tr(context, 'Refresh')),
          style: TextButton.styleFrom(
            foregroundColor: AppPalette.of(context).primary,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            textStyle: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _showEditReportSheet(BuildContext context, UserReport report) {
    if (!_sameAccount || report.userId != _viewer) return;
    String selectedLevel = report.severity;
    String editedDescription = report.description;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          _editContext = ctx;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .85,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReportActionHeading(
                      title: 'Update Your Report',
                      icon: Icons.edit_note,
                      showClose: true,
                      onClose: () => Navigator.pop(ctx),
                    ),
                    const SizedBox(height: 8),
                    ReportReference(reportId: report.id),
                    ReportPanel(
                      child: Text(
                        tr(
                          context,
                          'Edit the details of this observation. For new conditions, submit a new dated report.',
                        ),
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'Resident-selected flood level'),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['Low', 'Medium', 'High'].map((lvl) {
                        final isSel = selectedLevel == lvl;
                        Color btnColor = AppPalette.of(context).secondary;
                        if (lvl == 'Medium') {
                          btnColor = AppPalette.of(context).primary;
                        }
                        if (lvl == 'High') {
                          btnColor = AppPalette.of(context).tertiary;
                        }

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: OutlinedButton(
                              onPressed: () =>
                                  setModalState(() => selectedLevel = lvl),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: isSel
                                    ? btnColor
                                    : Colors.transparent,
                                side: BorderSide(color: btnColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                tr(context, lvl),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isSel ? Colors.white : btnColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'Your observation'),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: report.description,
                      onChanged: (value) => editedDescription = value,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: tr(
                          context,
                          'e.g., Water rising rapidly, ankle deep now...',
                        ),
                        filled: true,
                        fillColor: AppPalette.of(
                          context,
                        ).surfaceContainerLowest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppPalette.of(
                              context,
                            ).outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppPalette.of(context).onSurface,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final desc = editedDescription.trim();
                                if (desc.isEmpty || !_sameAccount) return;
                                setModalState(() => isSaving = true);
                                try {
                                  if (widget.saveEdit != null) {
                                    await widget.saveEdit!(
                                      report,
                                      selectedLevel,
                                      desc,
                                    );
                                  } else {
                                    await AppStateService.instance
                                        .updateExistingReport(
                                          reportId: report.id,
                                          expectedUpdatedAt:
                                              report.lastUpdatedByUser ??
                                              report.createdAt,
                                          floodLevel: selectedLevel,
                                          description: desc,
                                        );
                                  }
                                  if (!ctx.mounted || !_sameAccount) return;
                                  Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          tr(
                                            context,
                                            'Report updated successfully.',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted && _sameAccount) {
                                    setModalState(() => isSaving = false);
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text('Update failed: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.of(context).primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSaving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppPalette.of(context).onPrimary,
                                ),
                              )
                            : Text(
                                tr(context, 'Save update'),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.of(context).onPrimary,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      _editContext = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final historyBody = _accountError != null
        ? Center(
            child: TextButton(
              onPressed: _accountChanged ? null : _loadHistory,
              child: Text(
                _accountChanged
                    ? tr(context, _accountError!)
                    : '$_accountError Retry',
              ),
            ),
          )
        : _userId == null
        ? const Center(child: CircularProgressIndicator())
        : ListenableBuilder(
            listenable: _updates!,
            builder: (context, _) {
              final live = {
                for (final report in AppStateService.instance.reports)
                  report.id: report,
              };
              final history = _history!.page.reports
                  .where((report) => report.userId == _userId)
                  .map(
                    (report) => live[report.id] == null
                        ? report
                        : fresherReport(report, live[report.id]!),
                  )
                  .toList();

              if (history.isEmpty) {
                return _historyLayout(
                  Center(
                    child: Text(
                      !_history!.loaded
                          ? (_history!.loading
                                ? 'Loading report history...'
                                : 'History has not loaded.')
                          : _history!.page.fromCache
                          ? tr(
                              context,
                              'No saved history is available on this device.',
                            )
                          : tr(context, 'No reports on this page.'),
                      style: GoogleFonts.inter(
                        color: AppPalette.of(context).onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              return _historyLayout(
                ListView.builder(
                  padding: const EdgeInsets.only(
                    top: 8,
                    left: 16,
                    right: 16,
                    bottom: 24,
                  ),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final item = history[index];
                    return ReportHistoryCard(
                      key: ValueKey('history-${item.id}'),
                      report: item,
                      road: AppStateService.instance.roads
                          .where((road) => road.id == item.roadId)
                          .firstOrNull,
                      ownHistory: _ownHistory,
                      onEdit: () => _showEditReportSheet(context, item),
                    );
                  },
                ),
              );
            },
          );
    return Scaffold(
      appBar: widget.embedded
          ? const AppTopBar(inset: true)
          : AppTopBar(
              title: tr(context, 'Your reports'),
              showBackButton: true,
              showProfile: false,
              showSettingsAction: false,
              onBackPressed: () => Navigator.of(context).pop(),
              actions: [_refreshAction(context)],
            ),
      backgroundColor: AppPalette.of(context).surface,
      body: widget.embedded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 20, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          tr(context, 'Your reports'),
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.of(context).primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _refreshAction(context),
                    ],
                  ),
                ),
                Expanded(child: historyBody),
              ],
            )
          : historyBody,
    );
  }
}
