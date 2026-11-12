import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../services/app_state_service.dart';
import '../theme/app_palette.dart';

/// Reusable messages only. Choosing or saving a template never publishes an alert.
class AlertTemplateLibrary extends StatefulWidget {
  final ValueChanged<AlertTemplate> onUseTemplate;
  final List<AlertTemplate> Function()? loadTemplates;
  final Future<void> Function(AlertTemplate)? saveTemplate;
  final Future<void> Function(String)? deleteTemplate;
  const AlertTemplateLibrary({
    super.key,
    required this.onUseTemplate,
    this.loadTemplates,
    this.saveTemplate,
    this.deleteTemplate,
  });

  @override
  State<AlertTemplateLibrary> createState() => _AlertTemplateLibraryState();
}

class _AlertTemplateLibraryState extends State<AlertTemplateLibrary> {
  final _name = TextEditingController(),
      _title = TextEditingController(),
      _message = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _creating = false, _saving = false;
  int _severity = 1;
  String? _draftId, _error;
  final _examples = const [
    (
      'Flood warning',
      'Severe Flood Warning',
      'Water levels are rising rapidly in low-lying zones. Please avoid low-lying roads and head to safe shelters.',
      2,
    ),
    (
      'Evacuation',
      'Immediate Evacuation Notice',
      'Mandatory evacuation is now in effect for high-risk barangays. Proceed immediately to designated evacuation centers.',
      2,
    ),
    (
      'Road clearing',
      'Road Clearing & Operations',
      'Debris clearing operations are ongoing. Expect partial road closures and slow-moving traffic.',
      1,
    ),
    (
      'Heavy rain',
      'Heavy Rainfall Advisory',
      'Continuous heavy rainfall expected over the next several hours. Please monitor road water levels.',
      0,
    ),
    (
      'Typhoon alert',
      'Tropical Cyclone Wind Advisory',
      'Gale-force winds and heavy gusts forecast in the metro area. Exercise maximum caution outdoors.',
      2,
    ),
  ];

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  String _severityName(int value) =>
      ['Advisory', 'Warning', 'Critical'][value.clamp(0, 2)];
  Color _color(int value) {
    final p = AppPalette.of(context);
    return value == 0
        ? p.primary
        : value == 1
        ? p.warning
        : p.error;
  }

  Color _tint(int value) {
    final p = AppPalette.of(context);
    return value == 1
        ? p.warningContainer
        : value == 2
        ? p.scheme.errorContainer
        : p.primary.withValues(alpha: .08);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !_saving,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: .9,
            minChildSize: .6,
            maxChildSize: .96,
            expand: false,
            builder: (context, scroll) => Material(
              color: p.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListenableBuilder(
                listenable: AppStateService.instance,
                builder: (context, _) {
                  final templates =
                      widget.loadTemplates?.call() ??
                      AppStateService.instance.templates;
                  return SingleChildScrollView(
                    controller: scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(top: 12, bottom: 12),
                            decoration: BoxDecoration(
                              color: p.outlineVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr(context, 'Alert templates'),
                                      style: GoogleFonts.manrope(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: p.onSurface,
                                      ),
                                    ),
                                    if (!keyboard) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        tr(
                                          context,
                                          'Reusable messages. Nothing is published here.',
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.4,
                                          color: p.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: tr(context, 'Close'),
                                onPressed: () => Navigator.pop(context),
                                icon: Icon(
                                  Icons.close,
                                  color: p.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final items = [
                                _tab(
                                  '${tr(context, 'Saved templates')} (${templates.length})',
                                  !_creating,
                                  () => setState(() => _creating = false),
                                ),
                                _tab(
                                  tr(context, 'Create template'),
                                  _creating,
                                  () => setState(() => _creating = true),
                                ),
                              ];
                              return MediaQuery.textScalerOf(
                                            context,
                                          ).scale(12) >
                                          20 ||
                                      box.maxWidth < 260
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        items[0],
                                        const SizedBox(height: 6),
                                        items[1],
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(child: items[0]),
                                        const SizedBox(width: 8),
                                        Expanded(child: items[1]),
                                      ],
                                    );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_saving) const LinearProgressIndicator(),

                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_error != null) ...[
                                _info(_error!, error: true),
                                const SizedBox(height: 12),
                              ],
                              if (_creating)
                                _editor()
                              else
                                _library(templates, scroll),
                            ],
                          ),
                        ),
                        if (_creating) _footer(scroll),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback tap) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.primary : p.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: selected ? p.onPrimary : p.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    final p = AppPalette.of(context);
    return Material(
      color: p.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.outlineVariant.withValues(alpha: .4)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      tr(context, text),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppPalette.of(context).onSurface,
      ),
    ),
  );

  Widget _info(String text, {bool error = false}) {
    final p = AppPalette.of(context), color = error ? p.error : p.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    final p = AppPalette.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('Template name'),
                Text(
                  tr(
                    context,
                    'This name helps admins find the template. It is not included in the published alert.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: p.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const ValueKey('template-name'),
                  controller: _name,
                  maxLength: 60,
                  decoration: InputDecoration(
                    hintText: tr(context, 'e.g. Flood reminder'),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? tr(context, 'Enter a template name.')
                      : v.trim().length > 60
                      ? tr(context, 'Keep the name within 60 characters.')
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('Message for residents'),
                Text(
                  tr(context, 'These are the details copied into your alert.'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: p.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: Text(
                    tr(context, 'Start with an example (optional)'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                    ),
                  ),
                  children: [
                    _info(
                      tr(
                        context,
                        'Examples are not confirmed updates. Check every detail before use.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final example in _examples)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => setState(() {
                              _name.text = example.$1;
                              _title.text = example.$2;
                              _message.text = example.$3;
                              _severity = example.$4;
                            }),
                            child: Text(tr(context, example.$1)),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _label('Alert title'),
                TextFormField(
                  key: const ValueKey('template-title'),
                  controller: _title,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: tr(
                      context,
                      'Give the alert a short, clear title',
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? tr(context, 'Enter a title with at least 2 characters.')
                      : v!.trim().length > 120
                      ? tr(context, 'Keep the title within 120 characters.')
                      : null,
                ),
                const SizedBox(height: 12),
                _label('Instructions for residents'),
                TextFormField(
                  key: const ValueKey('template-message'),
                  controller: _message,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: tr(
                      context,
                      'Say what happened and what residents should do.',
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v?.trim().length ?? 0) < 10
                      ? tr(
                          context,
                          'Enter instructions with at least 10 characters.',
                        )
                      : v!.trim().length > 2000
                      ? tr(context, 'Keep the message within 2000 characters.')
                      : null,
                ),
                const SizedBox(height: 12),
                _label('How serious is it?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < 3; i++)
                      ChoiceChip(
                        label: Text(tr(context, _severityName(i))),
                        selected: _severity == i,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _severity == i ? _color(i) : p.onSurface,
                        ),
                        color: WidgetStatePropertyAll(
                          _severity == i ? _tint(i) : p.surfaceContainerLow,
                        ),
                        onSelected: (_) => setState(() => _severity = i),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: Text(
              tr(context, 'Message preview'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: p.primary,
              ),
            ),
            children: [
              _preview(_title.text.trim(), _message.text.trim(), _severity),
            ],
          ),
        ],
      ),
    );
  }

  Widget _preview(String title, String message, int severity) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _tint(severity),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _color(severity).withValues(alpha: .25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(context, _severityName(severity)),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _color(severity),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title.isEmpty ? tr(context, 'Your title appears here') : title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppPalette.of(context).onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message.isEmpty
              ? tr(context, 'Your instructions appear here.')
              : message,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppPalette.of(context).onSurface,
          ),
        ),
      ],
    ),
  );

  Widget _footer(ScrollController scroll) {
    final p = AppPalette.of(context);
    return Material(
      color: p.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, box) {
              final save = OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving
                    ? null
                    : () => _save(use: false, scroll: scroll),
                child: Text(
                  tr(context, 'Save template'),
                  textAlign: TextAlign.center,
                ),
              );
              final use = FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving
                    ? null
                    : () => _save(use: true, scroll: scroll),
                child: Text(
                  tr(context, _saving ? 'Saving…' : 'Save and use'),
                  textAlign: TextAlign.center,
                ),
              );
              return MediaQuery.textScalerOf(context).scale(12) > 20 ||
                      box.maxWidth < 260
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [save, const SizedBox(height: 6), use],
                    )
                  : Row(
                      children: [
                        Expanded(child: save),
                        const SizedBox(width: 8),
                        Expanded(child: use),
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _save({
    required bool use,
    required ScrollController scroll,
  }) async {
    if (_saving) return;
    if (_form.currentState?.validate() != true) {
      if (scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    FocusScope.of(context).unfocus();
    final template = AlertTemplate(
      id: _draftId ??= DateTime.now().microsecondsSinceEpoch.toString(),
      label: _name.text.trim(),
      title: _title.text.trim(),
      message: _message.text.trim(),
      severity: _severity,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.saveTemplate?.call(template) ??
              AppStateService.instance.addAlertTemplate(template))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() => _saving = false);
      if (use) {
        Navigator.pop(context);
        widget.onUseTemplate(template);
      } else {
        setState(() {
          _creating = false;
          _draftId = null;
          _name.clear();
          _title.clear();
          _message.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, 'Template saved. No alert was published.'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr(
            context,
            'Could not confirm the save. Your draft is still here. Check your connection and retry.',
          );
        });
      }
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Widget _library(List<AlertTemplate> templates, ScrollController scroll) {
    final p = AppPalette.of(context);
    if (templates.isEmpty) {
      return _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label('No saved templates yet'),
            Text(
              tr(context, 'Create a reusable message for your next alert.'),
              style: TextStyle(fontSize: 13, height: 1.4, color: p.onSurface),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => setState(() => _creating = true),
              child: Text(tr(context, 'Create template')),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _info(
          tr(
            context,
            'Use a template to fill your alert draft. Review the details before publishing.',
          ),
        ),
        const SizedBox(height: 12),
        for (final template in templates)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          template.label,
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: p.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: tr(context, 'Delete template'),
                        icon: Icon(
                          Icons.delete_outline,
                          color: p.onSurfaceVariant,
                        ),
                        onPressed: () => _delete(template, scroll),
                      ),
                    ],
                  ),
                  Text(
                    tr(context, _severityName(template.severity)),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _color(template.severity),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    template.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    template.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _view(template),
                        child: Text(tr(context, 'View message')),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onUseTemplate(template);
                        },
                        child: Text(tr(context, 'Use template')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _view(AlertTemplate template) => showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(template.label),
      content: _preview(template.title, template.message, template.severity),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr(context, 'Close')),
        ),
      ],
    ),
  );

  Future<void> _delete(AlertTemplate template, ScrollController scroll) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(tr(context, 'Delete template?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(template.label),
            const SizedBox(height: 10),
            Text(
              tr(
                context,
                'This removes the saved message. Published alerts stay unchanged.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(context, 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(context, 'Delete')),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.deleteTemplate?.call(template.id) ??
              AppStateService.instance.deleteAlertTemplate(template.id))
          .timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr(
            context,
            'Could not confirm deletion. Check your connection before retrying.',
          );
        });
      }
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }
}
