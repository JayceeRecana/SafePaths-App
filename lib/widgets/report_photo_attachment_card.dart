import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import 'report_workflow_ui.dart';

/// Attachment presentation only; the form retains picking/uploading/removal.
class ReportPhotoAttachmentCard extends StatelessWidget {
  final ImageProvider<Object>? preview;
  final bool processing, embedded;
  final String sourceHint;
  final String? label;
  final VoidCallback? onPick, onRemove;
  const ReportPhotoAttachmentCard({
    super.key,
    this.preview,
    this.processing = false,
    this.embedded = false,
    this.sourceHint = 'Camera or gallery',
    this.label,
    this.onPick,
    this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final enabled = !processing && onPick != null;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.photo_outlined, size: 19, color: p.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(
                  context,
                  preview == null
                      ? label ?? 'Photo evidence'
                      : 'Photo attached',
                ),
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: p.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (processing)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                Text(
                  tr(context, 'Validating and processing photo...'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.5,
                    color: p.onSurface,
                  ),
                ),
              ],
            ),
          )
        else if (preview != null) ...[
          Container(
            height: 220,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image(
              image: preview!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      context,
                      'Photo preview unavailable. Choose another photo.',
                    ),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: p.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? onPick : null,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(
                  tr(context, 'Change photo'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(
                  tr(context, 'Remove photo'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ] else
          Material(
            color: p.primary.withValues(alpha: p.isDark ? .06 : .035),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: p.primary.withValues(alpha: .25)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPick : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 148),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 36,
                        color: p.primary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        tr(context, 'Add Photo'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: p.primary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        tr(context, sourceHint),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.5,
                          color: p.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          tr(
            context,
            'JPG or PNG, up to 10 MB. Add only a photo you can take safely.',
          ),
          style: GoogleFonts.inter(
            fontSize: 11,
            height: 1.5,
            color: p.onSurfaceVariant,
          ),
        ),
      ],
    );
    return embedded
        ? content
        : ReportPanel(padding: const EdgeInsets.all(16), child: content);
  }
}
