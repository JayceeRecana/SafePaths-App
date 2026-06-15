import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_top_bar.dart';
import '../../services/app_state_service.dart';

class BroadcastAlertScreen extends StatefulWidget {
  const BroadcastAlertScreen({super.key});

  @override
  State<BroadcastAlertScreen> createState() => _BroadcastAlertScreenState();
}

class _BroadcastAlertScreenState extends State<BroadcastAlertScreen> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  int _severity = 1;
  bool _sendPush = true;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Broadcast Alert',
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PUBLIC WARNING',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: AppColors.tertiary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Emergency Alert Composer',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 18),
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

    await AppStateService.instance.broadcastAlert(title, message, severityText);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert sent to all active users.')),
      );
      // Only pop when pushed as a route — not when used as the Alerts tab.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
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