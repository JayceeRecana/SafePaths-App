import 'package:flutter/material.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../services/app_state_service.dart';
import 'map_dashboard_screen.dart';
import 'route_planner_screen.dart';
import 'notifications_screen.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  int _currentIndex = 0;
  bool _isLoading = true;
  final GlobalKey<MapDashboardScreenState> _mapDashboardKey = GlobalKey<MapDashboardScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      MapDashboardScreen(key: _mapDashboardKey),
      const RoutePlannerScreen(),
      const NotificationsScreen(),
    ];
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
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
