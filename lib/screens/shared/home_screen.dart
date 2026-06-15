import 'package:flutter/material.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../user/map_dashboard_screen.dart';
import '../user/notifications_screen.dart';
import '../admin/admin_panel_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final GlobalKey<MapDashboardScreenState> _mapDashboardKey = GlobalKey<MapDashboardScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      MapDashboardScreen(key: _mapDashboardKey),
      const SizedBox.shrink(), // Placeholder for Planner
      const NotificationsScreen(),
      const AdminPanelScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex == 0 &&
                _mapDashboardKey.currentState?.isRoutePlanningMode == true
            ? 1 // Show PLANNER as active when in route planning mode
            : (_currentIndex == 0 ? 0 : (_currentIndex == 2 ? 2 : 0)), // Note: BottomNavBar handles MAP, PLANNER, ALERTS, but not Admin directly. Wait! Let's check BottomNavBar code.
        onTap: (index) {
          if (index == 1) {
            setState(() {
              _currentIndex = 0;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _mapDashboardKey.currentState?.enterRoutePlanningMode();
            });
          } else {
            if (index == 0) {
              // Tapping MAP exits route planning mode if active
              _mapDashboardKey.currentState?.exitRoutePlanningMode();
            }
            setState(() {
              _currentIndex = index == 2 ? 2 : (index == 3 ? 3 : 0);
            });
          }
        },
      ),
    );
  }
}
