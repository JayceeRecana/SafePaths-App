import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';

class BroadcastAlertScreen extends StatefulWidget {
  final bool isStandalone;
  const BroadcastAlertScreen({super.key, this.isStandalone = false});

  @override
  State<BroadcastAlertScreen> createState() => _BroadcastAlertScreenState();
}

class _BroadcastAlertScreenState extends State<BroadcastAlertScreen> {
  final ScrollController _scrollController = ScrollController();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  int _severity = 1;
  bool _sendPush = true;

  @override
  void dispose() {
    _scrollController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Broadcast Alert',
        showBackButton: widget.isStandalone,
        showProfile: true,
        showSettingsAction: true,
        onBackPressed: widget.isStandalone ? () {
          if (Navigator.canPop(context)) Navigator.pop(context);
        } : null,
      ),
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _label('QUICK TEMPLATES'),
                      GestureDetector(
                        onTap: () => _showAddTemplateDialog(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_circle_outline, size: 14, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text('Custom', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ListenableBuilder(
                      listenable: AppStateService.instance,
                      builder: (context, _) {
                        final templates = AppStateService.instance.templates;
                        return Row(
                          children: [
                            for (var t in templates) ...[
                              _buildTemplateChip(t.label, t.title, t.message, t.severity),
                              const SizedBox(width: 8),
                            ],
                          ],
                        );
                      }
                    ),
                  ),
                  const SizedBox(height: 24),
                  _label('ALERT TITLE'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Immediate Evacuation - Zone B',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('SEVERITY LEVEL'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _SeverityChip(
                        label: 'Advisory',
                        active: _severity == 0,
                        color: AppColors.primary,
                        onTap: () => setState(() => _severity = 0),
                      ),
                      const SizedBox(width: 8),
                      _SeverityChip(
                        label: 'Warning',
                        active: _severity == 1,
                        color: AppColors.partial,
                        onTap: () => setState(() => _severity = 1),
                      ),
                      const SizedBox(width: 8),
                      _SeverityChip(
                        label: 'Critical',
                        active: _severity == 2,
                        color: AppColors.tertiary,
                        onTap: () => setState(() => _severity = 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label('ALERT MESSAGE'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Provide clear instructions for residents.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _sendPush,
                    onChanged: (value) => setState(() => _sendPush = value),
                    title: Text(
                      'Send push notification immediately',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.tertiary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.tertiary, AppColors.tertiaryContainer],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.tertiary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _broadcastAlert,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.campaign_rounded, color: Colors.white),
                label: Text(
                  'Broadcast Alert',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  void _broadcastAlert() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete title and message.')),
      );
      return;
    }

    String severityText = 'Warning';
    if (_severity == 0) severityText = 'Advisory';
    if (_severity == 2) severityText = 'Critical';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Confirm Broadcast', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: const Text('Are you sure you want to broadcast this alert to all active users? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                
                await AppStateService.instance.broadcastAlert(title, message, severityText);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alert sent to all active users.')),
                  );
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.tertiary, foregroundColor: Colors.white),
              child: const Text('Broadcast Now'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTemplateChip(String label, String title, String message, int severity) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
      backgroundColor: AppColors.surfaceContainerHigh,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () {
        setState(() {
          _titleController.text = title;
          _messageController.text = message;
          _severity = severity;
        });
      },
    );
  }

  void _showAddTemplateDialog(BuildContext context) {
    final labelCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    int tempSeverity = 1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              title: Text('New Custom Template', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width, // Force dialog to expand to max width allowed by insetPadding
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    TextField(
                      controller: labelCtrl,
                      decoration: InputDecoration(
                        labelText: 'Short Label (e.g. Typhoon)',
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Alert Title',
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Alert Message',
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: tempSeverity,
                      decoration: InputDecoration(
                        labelText: 'Severity',
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Advisory')),
                        DropdownMenuItem(value: 1, child: Text('Warning')),
                        DropdownMenuItem(value: 2, child: Text('Critical')),
                      ],
                      onChanged: (val) => setDialogState(() => tempSeverity = val ?? 1),
                    ),
                  ],
                ),
              ),
            ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (labelCtrl.text.isNotEmpty && titleCtrl.text.isNotEmpty) {
                      AppStateService.instance.addAlertTemplate(
                        AlertTemplate(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          label: labelCtrl.text,
                          title: titleCtrl.text,
                          message: messageCtrl.text,
                          severity: tempSeverity,
                        ),
                      );
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    elevation: 0,
                  ),
                  child: Text('Save Template', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ],
            );
          }
        );
      },
    );
  }
}

class _SeverityChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _SeverityChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.16) : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? color : Colors.transparent),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? color : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}