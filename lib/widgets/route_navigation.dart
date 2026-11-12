import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/planned_route.dart';
import '../screens/user/navigation_screen.dart';
import '../services/routing_service.dart';

/// One shared handoff for the planner and preview. Recheck after the dialog:
/// accepting an earlier caution cannot authorize a newly closed route.
Future<bool> startRouteNavigation(
  BuildContext context,
  PlannedRoute route, {
  bool replacePreview = false,
  void Function(PlannedRoute)? onNavigate,
  NavigationAdmission Function(PlannedRoute)? assess,
}) async {
  final evaluate = assess ?? RoutingService.instance.navigationAdmission;
  var current = evaluate(route);
  void changed() {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Road conditions changed. Review the updated route before starting.',
            ),
          ),
        ),
      );
  }

  if (!current.route.canStartNavigation) {
    changed();
    return false;
  }
  if (current.requiresCaution) {
    final accepted =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            scrollable: true,
            title: Text(tr(context, 'Confirm Travel Conditions')),
            content: Text(
              tr(
                context,
                'This route may include flood risk or unconfirmed conditions, including areas without monitoring. Confirm local conditions and review the route before travel.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(tr(context, 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(tr(context, 'Continue with Caution')),
              ),
            ],
          ),
        ) ??
        false;
    if (!context.mounted || !accepted) return false;
    final latest = evaluate(route);
    if (!latest.route.canStartNavigation || latest.key != current.key) {
      changed();
      return false;
    }
    current = latest;
  }
  if (!context.mounted) return false;
  if (onNavigate != null) {
    onNavigate(current.route);
    return true;
  }
  final page = MaterialPageRoute<void>(
    builder: (_) => NavigationScreen(
      route: current.route,
      reviewedRiskKey: current.route.safetyStatus == 'critical'
          ? current.key
          : null,
    ),
  );
  if (replacePreview) {
    await Navigator.of(context).pushReplacement<void, void>(page);
  } else {
    await Navigator.of(context).push<void>(page);
  }
  return true;
}
