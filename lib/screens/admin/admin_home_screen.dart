import 'package:flutter/material.dart';
import '../../widgets/admin_bottom_nav_bar.dart';
import '../../services/app_state_service.dart';
import 'admin_panel_screen.dart';
import 'update_road_status_screen.dart';
import 'broadcast_alert_screen.dart';
import 'user_reports_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _hideNavBar = false;

  void _onSelectionChanged(bool hasSelection) {
    if (mounted) {
      setState(() {
        _hideNavBar = hasSelection;
      });
    }
  }

  List<Widget> get _screens => [
    const AdminPanelScreen(),
    UpdateRoadStatusScreen(onSelectionChanged: _onSelectionChanged),
    const BroadcastAlertScreen(),
    UserReportsScreen(onSelectionChanged: _onSelectionChanged),
  ];

  @override
  void initState() {
    super.initState();
    AppStateService.instance.initialize().then((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.fastOutSlowIn,
        child: _hideNavBar
            ? const SizedBox(width: double.infinity, height: 0)
            : AdminBottomNavBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
              ),
      ),
    );
  }
}