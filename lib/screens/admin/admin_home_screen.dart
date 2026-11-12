import '../../services/notification_service.dart';
import 'package:flutter/material.dart';
import '../../widgets/admin_bottom_nav_bar.dart';
import '../../services/app_state_service.dart';
import 'admin_panel_screen.dart';
import 'update_road_status_screen.dart';
import 'broadcast_alert_screen.dart';
import 'user_reports_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  final Future<void> Function()? initialize;
  final int Function(void Function(Map<String, dynamic>?) callback)? attachTap;
  final void Function(int owner)? detachTap;
  const AdminHomeScreen({
    super.key,
    this.initialize,
    this.attachTap,
    this.detachTap,
  });

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentIndex = 0;
  String? _notificationReportId;
  int _reportOpenRevision = 0;
  late final int _notificationTapOwner;
  bool _isLoading = true;
  final Map<int, bool> _selectionByTab = {};
  bool get _hideNavBar => _selectionByTab[_currentIndex] ?? false;

  void _onSelectionChanged(int tab, bool hasSelection) {
    if (mounted && (_selectionByTab[tab] ?? false) != hasSelection) {
      setState(() {
        _selectionByTab[tab] = hasSelection;
      });
    }
  }

  List<Widget> get _screens => [
    const AdminPanelScreen(),
    UpdateRoadStatusScreen(
      isActive: _currentIndex == 1,
      onSelectionChanged: (selected) => _onSelectionChanged(1, selected),
    ),
    const BroadcastAlertScreen(),
    UserReportsScreen(
      initialReportId: _notificationReportId,
      openRequestRevision: _reportOpenRevision,
      isActive: _currentIndex == 3,
      onSelectionChanged: (selected) => _onSelectionChanged(3, selected),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _notificationTapOwner =
        (widget.attachTap ?? NotificationService.instance.setOnNotificationTap)(
          (data) {
            final type = data?['type'];
            final reportTap = type is String && type.startsWith('report_');
            final reportId = data?['reportId'];
            if (reportTap &&
                reportId is String &&
                RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(reportId)) {
              _notificationReportId = reportId;
              _reportOpenRevision++;
            }
            if (mounted) setState(() => _currentIndex = reportTap ? 3 : 2);
          },
        );
    (widget.initialize ?? AppStateService.instance.initialize)()
        .then((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        })
        .catchError((Object _) {
          if (mounted) setState(() => _isLoading = false);
          AppStateService.instance.retrySync();
        });
  }

  @override
  void dispose() {
    (widget.detachTap ?? NotificationService.instance.clearOnNotificationTap)(
      _notificationTapOwner,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_hideNavBar) return;
        if (_currentIndex > 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.fastOutSlowIn,
          child: _hideNavBar
              ? const SizedBox(width: double.infinity, height: 0)
              : AdminBottomNavBar(
                  currentIndex: _currentIndex,
                  onTap: (index) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                ),
        ),
      ),
    );
  }
}
