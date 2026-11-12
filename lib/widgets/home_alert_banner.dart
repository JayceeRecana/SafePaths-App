import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

class HomeAlertBanner extends StatelessWidget {
  final String title, severity;
  final String? roadName;
  final VoidCallback onOpen, onDismiss;
  const HomeAlertBanner({
    super.key,
    required this.title,
    required this.severity,
    this.roadName,
    required this.onOpen,
    required this.onDismiss,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final background = severity == 'Critical'
        ? p.errorContainer
        : severity == 'Warning'
        ? p.warningContainer
        : p.primaryContainer;
    final foreground = severity == 'Critical'
        ? p.onErrorContainer
        : severity == 'Warning'
        ? p.onWarningContainer
        : p.onPrimaryContainer;
    final label = severity == 'Critical'
        ? 'CRITICAL ALERT'
        : severity == 'Warning'
        ? 'WARNING'
        : 'ADVISORY';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
              child: Row(
                children: [
                  Icon(
                    severity == 'Critical'
                        ? Icons.emergency_rounded
                        : Icons.info_outline,
                    color: foreground,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, label),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: foreground,
                          ),
                        ),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                        if (roadName?.isNotEmpty == true)
                          Text(
                            roadName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: foreground,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, 'Dismiss alert'),
                    onPressed: onDismiss,
                    color: foreground,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
