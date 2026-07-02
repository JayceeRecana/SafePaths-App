import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../services/weather_service.dart';
import '../../widgets/app_top_bar.dart';

class WeatherSimulatorScreen extends StatelessWidget {
  const WeatherSimulatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(
        title: 'Weather Simulator',
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
      ),
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Development Tools',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'System Drill\nControls',
              style: GoogleFonts.manrope(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: AppColors.onSurface,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 24),
            
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<WeatherState>(
                    valueListenable: SimulatedWeatherService.instance.listenable,
                    builder: (context, currentState, _) {
                      final weatherService = SimulatedWeatherService.instance;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.thunderstorm, size: 20, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Weather State',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: weatherService.isOverrideMode 
                                      ? AppColors.errorContainer 
                                      : AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  weatherService.isOverrideMode 
                                      ? 'Simulation Active' 
                                      : 'Live Polling Active',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: weatherService.isOverrideMode 
                                        ? AppColors.notPassable 
                                        : AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Manually override the weather to test how the Predictive Risk Model escalates vulnerable roads. Click "Reset to Live Data" to turn off the simulation and resume real-time weather polling.',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: WeatherState.values.map((state) {
                              final isSelected = currentState == state;
                              final color = weatherService.getWeatherColor(state);
                              
                              return ChoiceChip(
                                label: Text(weatherService.getWeatherDescription(state)),
                                selected: isSelected,
                                selectedColor: color.withValues(alpha: 0.2),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                labelStyle: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? color : AppColors.onSurfaceVariant,
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    weatherService.setWeather(state);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        SimulatedWeatherService.instance.toggleOverride(false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Resumed live weather polling')),
                        );
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('Reset to Live Data'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
