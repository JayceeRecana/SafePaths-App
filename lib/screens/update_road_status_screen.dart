import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../widgets/app_top_bar.dart';

class UpdateRoadStatusScreen extends StatefulWidget {
  const UpdateRoadStatusScreen({super.key});

  @override
  State<UpdateRoadStatusScreen> createState() => _UpdateRoadStatusScreenState();
}

class _UpdateRoadStatusScreenState extends State<UpdateRoadStatusScreen> {
  final _roadNameController = TextEditingController();
  final _notesController = TextEditingController();
  int _selectedStatus = 1;
  bool _postToAlerts = true;

  @override
  void dispose() {
    _roadNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Update Road Status',
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
              'ROAD CONTROL',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Set Current Passability',
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
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('ROAD NAME'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _roadNameController,
                    decoration: const InputDecoration(hintText: 'e.g. MacArthur Highway'),
                  ),
                  const SizedBox(height: 18),
                  _label('PASSABILITY STATUS'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatusChip(
                        label: 'Passable',
                        color: AppColors.passable,
                        selected: _selectedStatus == 0,
                        onTap: () => setState(() => _selectedStatus = 0),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(
                        label: 'Partial',
                        color: AppColors.partial,
                        selected: _selectedStatus == 1,
                        onTap: () => setState(() => _selectedStatus = 1),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(
                        label: 'Not Passable',
                        color: AppColors.notPassable,
                        selected: _selectedStatus == 2,
                        onTap: () => setState(() => _selectedStatus = 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _label('FIELD NOTES'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Describe flood depth, obstruction, and traffic condition.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _postToAlerts,
                    onChanged: (value) => setState(() => _postToAlerts = value),
                    title: Text(
                      'Notify residents about this update',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _PrimaryActionButton(
              label: 'Publish Status Update',
              icon: Icons.publish_rounded,
              onTap: _publishStatus,
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  void _publishStatus() {
    if (_roadNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the road name.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Road status updated successfully.')),
    );
    Navigator.of(context).pop();
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.18) : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : Colors.transparent, width: 1.4),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? color : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}