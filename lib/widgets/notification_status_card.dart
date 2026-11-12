import 'settings_preference_card.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/notification_service.dart';

class NotificationStatusCard extends StatefulWidget {
  final bool reportUpdates, settingsStyle;
  const NotificationStatusCard({
    super.key,
    this.reportUpdates = false,
    this.settingsStyle = false,
  });
  @override
  State<NotificationStatusCard> createState() => _NotificationStatusCardState();
}

class _NotificationStatusCardState extends State<NotificationStatusCard>
    with WidgetsBindingObserver {
  final service = NotificationService.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    service.refreshReadiness();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      service.refreshReadiness();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: service.readiness,
    builder: (context, status, _) {
      final title = tr(
        context,
        widget.reportUpdates
            ? 'Report update notifications'
            : 'Emergency notifications',
      );
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(switch (status) {
              NotificationReadiness.checking => tr(
                context,
                'Checking notification permissions…',
              ),
              NotificationReadiness.ready => tr(
                context,
                'Notifications are allowed. Delivery still depends on your connection and phone settings.',
              ),
              NotificationReadiness.denied => tr(
                context,
                'Notifications are blocked. Allow them in your phone settings.',
              ),
              NotificationReadiness.channelDisabled => tr(
                context,
                widget.reportUpdates
                    ? 'The report update channel is disabled. Enable it in your phone settings.'
                    : 'The SafePaths alert channel is disabled. Enable it in your phone settings.',
              ),
              NotificationReadiness.unavailable => tr(
                context,
                'Notification status could not be checked. You can still read received alerts in the app.',
              ),
            }),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              widget.reportUpdates
                  ? 'Force-stopping the app can stop notifications until you reopen it. Check report history when you return.'
                  : 'Force-stopping the app can stop push alerts until you reopen it. Check Alerts when you return.',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: status == NotificationReadiness.checking
                    ? null
                    : () => service.refreshReadiness(requestPermission: true),
                child: Text(tr(context, 'Check permissions')),
              ),
              TextButton(
                onPressed: () async {
                  final opened = await Geolocator.openAppSettings();
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr(
                            context,
                            'Open your phone settings and select SafePaths notifications.',
                          ),
                        ),
                      ),
                    );
                  }
                },
                child: Text(tr(context, 'Phone settings')),
              ),
            ],
          ),
        ],
      );
      if (widget.settingsStyle)
        return SettingsPreferenceCard(
          title: title,
          icon: Icons.notifications_active_outlined,
          child: body,
        );
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              body,
            ],
          ),
        ),
      );
    },
  );
}
