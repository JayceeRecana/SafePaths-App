import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/settings_preference_card.dart';

/// Local directory: independent of login, location and backend availability.
class EmergencyHotlinesScreen extends StatelessWidget {
  const EmergencyHotlinesScreen({super.key, this.openLink});

  final Future<bool> Function(Uri)? openLink;
  static const source = 'https://valenzuela.gov.ph/emergency-hotlines-numbers/';
  static const contacts = [
    (
      'Disaster response',
      'City Disaster Risk Reduction and Management Office',
      Icons.support_agent_rounded,
      [
        ('(02) 8352 5000', '+63283525000'),
        ('(02) 8292 1405', '+63282921405'),
        ('0919 009 4045', '+639190094045'),
        ('0917 881 1639', '+639178811639'),
      ],
    ),
    (
      'Fire station',
      'Valenzuela City Fire Station',
      Icons.local_fire_department_outlined,
      [('(02) 8292 3519', '+63282923519')],
    ),
    (
      'Police station',
      'Valenzuela City Police Station',
      Icons.local_police_outlined,
      [('(02) 8352 4000', '+63283524000')],
    ),
    (
      'Emergency hospital',
      'Valenzuela City Emergency Hospital',
      Icons.local_hospital_outlined,
      [('(02) 8352 6000', '+63283526000')],
    ),
    (
      'Medical center',
      'Valenzuela Medical Center',
      Icons.medical_services_outlined,
      [('(02) 8294 6711', '+63282946711')],
    ),
  ];

  Future<void> _open(BuildContext context, Uri uri) async {
    var opened = false;
    try {
      opened =
          await (openLink?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      /* Keep the directory available when no handler exists. */
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              uri.scheme == 'tel'
                  ? 'Could not open the dialer. Copy the number and dial it on your phone.'
                  : 'Could not open the source website. Please try again later.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppTopBar(
        title: tr(context, 'Emergency hotlines'),
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Valenzuela City',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: p.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              'Tap a number to open your phone dialer. You choose whether to place the call.',
            ),
            style: TextStyle(color: p.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 18),
          for (final contact in contacts) ...[
            SettingsPreferenceCard(
              title: tr(context, contact.$1),
              icon: contact.$3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    contact.$2,
                    style: TextStyle(color: p.onSurface, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  for (final number in contact.$4)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Material(
                        color: p.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _open(
                                  context,
                                  Uri(scheme: 'tel', path: number.$2),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.call_outlined,
                                        color: p.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          number.$1,
                                          style: TextStyle(
                                            color: p.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  '${tr(context, 'Copy number')}: ${number.$1}',
                              color: p.primary,
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: number.$1),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr(context, 'Phone number copied.'),
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy_outlined, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          SettingsPreferenceCard(
            title: tr(context, 'About this directory'),
            icon: Icons.info_outline_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(
                    context,
                    'Source: Valenzuela City government. Numbers checked on November 2, 2026.',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    context,
                    'Numbers are saved in the app. Calls require phone service; charges may apply. SafePaths does not place calls or dispatch responders.',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _open(context, Uri.parse(source)),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(tr(context, 'View official source')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
