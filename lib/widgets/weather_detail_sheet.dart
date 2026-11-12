import '../theme/app_palette.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/weather_service.dart';
import '../config/app_environment.dart';

class WeatherDetailSheet {
  static void show(
    BuildContext context, {
    SimulatedWeatherService? weatherService,
    WeatherState? weatherState,
  }) {
    final service = weatherService ?? SimulatedWeatherService.instance;
    final state = weatherState ?? service.currentState;

    final weatherColor = service.getWeatherColor(state);
    final weatherIcon = service.getWeatherIcon(state);
    final weatherDesc = service.getWeatherDescription(state);
    final intensity = service.precipitationIntensity;
    final wind = service.windSpeed;
    final multiplier = service.weatherMultiplier;
    final isOverride = service.isOverrideMode;

    String guidanceTitle;
    String guidanceText;
    IconData guidanceIcon;
    Color guidanceColor;

    if (state == WeatherState.clear ||
        state == WeatherState.partlyCloudy ||
        state == WeatherState.lightRain) {
      guidanceTitle = 'System Status: Normal';
      guidanceText =
          'No severe weather detected. Standard routing algorithms are active without weather penalties.';
      guidanceIcon = Icons.check_circle_outline;
      guidanceColor = Colors.green;
    } else if (state == WeatherState.moderateRain) {
      guidanceTitle = 'System Status: Elevated';
      guidanceText =
          'Precipitation detected. Risk propagation model is actively monitoring network vulnerability.';
      guidanceIcon = Icons.warning_amber_rounded;
      guidanceColor = Colors.amber;
    } else {
      guidanceTitle = 'System Status: Critical';
      guidanceText =
          'High risk weather active. SafePaths is actively penalizing flood-prone road edges and calculating detours.';
      guidanceIcon = Icons.gpp_bad_outlined;
      guidanceColor = Colors.red;
    }

    if (AppEnvironment.sparkCoreEnabled && service.isDataStale) {
      guidanceTitle = 'Weather unavailable';
      guidanceText =
          'Current weather could not be confirmed. The previous risk result is retained. Check the latest local advisories.';
      guidanceIcon = Icons.cloud_off_outlined;
      guidanceColor = Colors.grey;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.of(context).surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.of(
                        context,
                      ).outlineVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${service.temperature.toStringAsFixed(1)}°',
                      style: GoogleFonts.manrope(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.of(context).onSurface,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        tr(context, 'C'),
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.of(context).onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Icon(weatherIcon, color: weatherColor, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              weatherDesc,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.of(context).onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppEnvironment.area.name,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppPalette.of(context).onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isOverride
                        ? AppPalette.of(context).errorContainer
                        : AppPalette.of(
                            context,
                          ).primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isOverride
                          ? AppPalette.of(
                              context,
                            ).notPassable.withValues(alpha: 0.3)
                          : AppPalette.of(
                              context,
                            ).primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOverride
                            ? Icons.science_outlined
                            : Icons.sensors_outlined,
                        size: 16,
                        color: isOverride
                            ? AppPalette.of(context).notPassable
                            : AppPalette.of(context).primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOverride
                              ? tr(context, 'Simulation Active (Drill Mode)')
                              : tr(
                                  context,
                                  'Open-Meteo weather model estimate',
                                ),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isOverride
                                ? AppPalette.of(context).notPassable
                                : AppPalette.of(context).primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (AppEnvironment.sparkCoreEnabled &&
                    service.getHourlyForecast().isEmpty)
                  const Text('Hourly forecast unavailable.'),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: service.getHourlyForecast().length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final hourData = service.getHourlyForecast()[index];
                      final time = hourData['time'] as DateTime;
                      final temp = hourData['temperature'] as double;
                      final rainChance = hourData['rainChance'] as double;
                      final forecastState = hourData['state'] as WeatherState;
                      final icon = service.getWeatherIcon(
                        forecastState,
                        time: time,
                      );
                      final color = service.getWeatherColor(
                        forecastState,
                        time: time,
                      );

                      String hourStr = time.hour > 12
                          ? '${time.hour - 12}'
                          : (time.hour == 0 ? '12' : '${time.hour}');
                      String amPm = time.hour >= 12 ? 'PM' : 'AM';

                      return Container(
                        width: 60,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? color.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: index == 0
                                ? color.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              index == 0
                                  ? tr(context, 'Now')
                                  : '$hourStr $amPm',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: index == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: index == 0
                                    ? color
                                    : AppPalette.of(context).onSurfaceVariant,
                              ),
                            ),
                            Icon(icon, color: color, size: 22),
                            Text(
                              '${temp.toStringAsFixed(0)}°',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.of(context).onSurface,
                              ),
                            ),
                            Text(
                              '${rainChance.toStringAsFixed(0)}%',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        context: context,
                        icon: Icons.water_drop_outlined,
                        title: tr(context, 'Rainfall Rate'),
                        value: '${intensity.toStringAsFixed(1)} mm/h',
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        context: context,
                        icon: Icons.air_outlined,
                        title: tr(context, 'Wind Speed'),
                        value: '${wind.toStringAsFixed(1)} m/s',
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppPalette.of(
                        context,
                      ).outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.query_stats_outlined,
                            color: AppPalette.of(context).primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tr(context, 'Predictive Risk Impact'),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tr(context, 'Risk Propagation Factor:'),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.of(context).onSurfaceVariant,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: multiplier > 0.0
                                  ? AppPalette.of(context).errorContainer
                                  : AppPalette.of(
                                      context,
                                    ).primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${multiplier.toStringAsFixed(1)}x',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: multiplier > 0.0
                                    ? AppPalette.of(context).notPassable
                                    : AppPalette.of(context).primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        multiplier > 0.0
                            ? tr(
                                context,
                                'Active weather adds a risk bonus to neighboring roads based on connectivity and vulnerability.',
                              )
                            : tr(
                                context,
                                'Clear weather does not propagate precipitation risk across the study area network.',
                              ),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppPalette.of(context).onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: guidanceColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: guidanceColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(guidanceIcon, color: guidanceColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              guidanceTitle,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: guidanceColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              guidanceText,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppPalette.of(context).onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.of(context).primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      tr(context, 'Dismiss'),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.of(context).onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildMetricCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.of(context).outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppPalette.of(context).onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppPalette.of(context).onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
