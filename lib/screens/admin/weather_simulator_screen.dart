import '../../theme/app_palette.dart';
import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/weather_service.dart';
import '../../widgets/app_top_bar.dart';
import '../../config/app_environment.dart';

class WeatherSimulatorScreen extends StatefulWidget {
  const WeatherSimulatorScreen({super.key});

  @override
  State<WeatherSimulatorScreen> createState() => _WeatherSimulatorScreenState();
}

class _WeatherSimulatorScreenState extends State<WeatherSimulatorScreen> {
  bool _isResetting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: tr(context, 'Weather Simulator'),
        showBackButton: true,
        showProfile: false,
        showSettingsAction: false,
      ),
      backgroundColor: AppPalette.of(context).surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Development Tools'),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: AppPalette.of(context).primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr(context, 'System Drill\nControls'),
              style: GoogleFonts.manrope(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: AppPalette.of(context).onSurface,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppPalette.of(context).surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppPalette.of(
                    context,
                  ).outlineVariant.withValues(alpha: 0.2),
                ),
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
                    valueListenable:
                        SimulatedWeatherService.instance.listenable,
                    builder: (context, currentState, _) {
                      final weatherService = SimulatedWeatherService.instance;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.thunderstorm,
                                size: 20,
                                color: AppPalette.of(context).primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tr(context, 'Weather State'),
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.of(context).onSurface,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: weatherService.isOverrideMode
                                      ? AppPalette.of(context).errorContainer
                                      : AppPalette.of(
                                          context,
                                        ).primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  weatherService.isOverrideMode
                                      ? tr(context, 'Simulation Active')
                                      : tr(context, 'Live Polling Active'),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: weatherService.isOverrideMode
                                        ? AppPalette.of(context).notPassable
                                        : AppPalette.of(context).primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppPalette.of(
                                context,
                              ).primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppPalette.of(
                                  context,
                                ).primary.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: AppPalette.of(context).primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tr(
                                      context,
                                      'Manually override the weather to test how the Predictive Risk Model escalates vulnerable roads. Click "Reset to Live Data" to turn off the simulation and resume real-time weather polling.',
                                    ),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppPalette.of(
                                        context,
                                      ).onSurfaceVariant,
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
                              final color = weatherService.getWeatherColor(
                                state,
                              );

                              return ChoiceChip(
                                label: Text(
                                  weatherService.getWeatherDescription(state),
                                ),
                                selected: isSelected,
                                selectedColor: color.withValues(alpha: 0.2),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                labelStyle: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? color
                                      : AppPalette.of(context).onSurfaceVariant,
                                ),
                                onSelected: (selected) {
                                  if (selected && !isSelected) {
                                    _confirmAndSetWeather(
                                      context,
                                      weatherService,
                                      state,
                                    );
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
                      onPressed: _isResetting
                          ? null
                          : () async {
                              setState(() => _isResetting = true);
                              try {
                                await SimulatedWeatherService.instance
                                    .toggleOverride(false);
                                await SimulatedWeatherService.instance
                                    .fetchLiveWeather();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr(
                                          context,
                                          'Drill disabled. Live weather appears after a successful server refresh.',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'The weather change was not confirmed. Keep the previous setting and retry.',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted)
                                  setState(() => _isResetting = false);
                              }
                            },
                      icon: _isResetting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppPalette.of(context).primary,
                              ),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        _isResetting
                            ? tr(context, 'Fetching Live Data...')
                            : tr(context, 'Reset to Live Data'),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppPalette.of(context).primary,
                        side: BorderSide(color: AppPalette.of(context).primary),
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

  void _confirmAndSetWeather(
    BuildContext context,
    SimulatedWeatherService weatherService,
    WeatherState state,
  ) {
    final stateName = weatherService.getWeatherDescription(state);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          scrollable: true,
          backgroundColor: AppPalette.of(context).surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppPalette.of(context).warning,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(context, 'Activate Drill?'),
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            tr(
                  context,
                  AppEnvironment.sparkCoreEnabled || !AppEnvironment.isFieldTest
                      ? 'Set {state} as a weather drill for {area}. Simulated conditions can affect predictions shown to residents in this area. The drill expires after 30 minutes and is not an official weather warning.'
                      : 'Set {state} as a weather drill for {area}. Simulated conditions can affect predictions shown to residents in this area. This drill stays active until changed or reset.',
                )
                .replaceAll('{state}', stateName)
                .replaceAll('{area}', AppEnvironment.area.name),
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppPalette.of(context).onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                tr(context, 'Cancel'),
                style: GoogleFonts.inter(
                  color: AppPalette.of(context).onSurfaceVariant,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.of(context).warning,
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                try {
                  await weatherService.setWeather(state);
                } catch (e) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'The weather drill was not confirmed. Please retry.',
                        ),
                      ),
                    );
                  return;
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '⚡ Weather drill active: $stateName (Auto-expires in 30m)',
                    ),
                    backgroundColor: AppPalette.of(context).warning,
                  ),
                );
              },
              child: Text(
                tr(context, 'Activate Drill'),
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
