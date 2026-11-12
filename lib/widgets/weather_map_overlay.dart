import '../config/app_environment.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/weather_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WeatherMapOverlay
//
// Drop this as a Stack layer OVER AppMap. It reads from
// SimulatedWeatherService.instance.listenable and renders:
//   • Animated rain particles  (canvas, density/speed scale with state)
//   • Atmospheric colour tint  (semi-transparent gradient overlay)
//   • Edge flood-glow pulse    (heavy rain / typhoon)
//   • Storm warning banner     (heavy rain / typhoon)
//
// Admin road-status logic is untouched — this widget adds nothing to
// AppStateService and writes nothing to Firestore.
// ─────────────────────────────────────────────────────────────────────────────

class WeatherMapOverlay extends StatefulWidget {
  const WeatherMapOverlay({super.key});

  @override
  State<WeatherMapOverlay> createState() => _WeatherMapOverlayState();
}

class _WeatherMapOverlayState extends State<WeatherMapOverlay>
    with TickerProviderStateMixin {
  // ── animation controllers ──────────────────────────────────────────────────
  late final AnimationController _rainController;
  late final AnimationController _pulseController;
  late final AnimationController _tintController;

  WeatherState _current = WeatherState.clear;
  WeatherState _previous = WeatherState.clear;

  // ── rain particle pool ─────────────────────────────────────────────────────
  final List<_RainDrop> _drops = [];
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();

    _current = SimulatedWeatherService.instance.currentState;

    _rainController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 16), // ~60 fps tick
          )
          ..addListener(_tickRain)
          ..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _tintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    SimulatedWeatherService.instance.listenable.addListener(_onWeatherChanged);
    _rebuildDrops(Size.zero); // will rebuild properly on first paint
  }

  @override
  void dispose() {
    SimulatedWeatherService.instance.listenable.removeListener(
      _onWeatherChanged,
    );
    _rainController.dispose();
    _pulseController.dispose();
    _tintController.dispose();
    super.dispose();
  }

  void _onWeatherChanged() {
    if (!mounted) return;
    setState(() {
      _previous = _current;
      _current = SimulatedWeatherService.instance.currentState;
    });
    _tintController.forward(from: 0);
    // Pulse only during heavy weather
    if (_current == WeatherState.heavyRain ||
        _current == WeatherState.typhoon) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
    }
  }

  // ── rain particle helpers ──────────────────────────────────────────────────

  int _dropCount(WeatherState s) {
    switch (s) {
      case WeatherState.clear:
      case WeatherState.partlyCloudy:
        return 0;
      case WeatherState.lightRain:
        return 60;
      case WeatherState.moderateRain:
        return 140;
      case WeatherState.heavyRain:
        return 280;
      case WeatherState.typhoon:
        return 450;
    }
  }

  double _dropSpeed(WeatherState s) {
    switch (s) {
      case WeatherState.clear:
      case WeatherState.partlyCloudy:
        return 0;
      case WeatherState.lightRain:
        return 4.5;
      case WeatherState.moderateRain:
        return 7.5;
      case WeatherState.heavyRain:
        return 11.0;
      case WeatherState.typhoon:
        return 18.0;
    }
  }

  double _dropAngle(WeatherState s) {
    // typhoon has a strong horizontal wind angle
    switch (s) {
      case WeatherState.clear:
      case WeatherState.partlyCloudy:
        return 0.0;
      case WeatherState.typhoon:
        return 0.45; // ~26° from vertical
      case WeatherState.heavyRain:
        return 0.20;
      case WeatherState.moderateRain:
        return 0.10;
      case WeatherState.lightRain:
        return 0.05;
    }
  }

  void _rebuildDrops(Size size) {
    final count = _dropCount(_current);
    _drops.clear();
    if (count == 0 || size == Size.zero) return;
    for (var i = 0; i < count; i++) {
      _drops.add(_RainDrop.random(_rng, size));
    }
  }

  void _tickRain() {
    if (!mounted) return;
    // Animation ticks can precede layout during hot reload. Use the last
    // laid-out size, and wait if this render box has never been laid out.
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final size = box.size;
    if (size == Size.zero) return;

    // Ensure drop count matches current weather
    final target = _dropCount(_current);
    if (_drops.length != target) {
      setState(() => _rebuildDrops(size));
    }

    final speed = _dropSpeed(_current);
    final angle = _dropAngle(_current);
    if (speed == 0) {
      if (_drops.isNotEmpty) setState(() => _drops.clear());
      return;
    }

    // No setState needed! The painter will repaint automatically via the controller.
    for (final d in _drops) {
      d.x += speed * angle;
      d.y += speed * (1.0 + d.speedVariance);
      if (d.y > size.height + 20 || d.x > size.width + 20) {
        d.reset(_rng, size);
      }
    }
  }

  // ── tint config ────────────────────────────────────────────────────────────

  Color _tintColor(WeatherState s) {
    switch (s) {
      case WeatherState.clear:
      case WeatherState.partlyCloudy:
        return Colors.transparent;
      case WeatherState.lightRain:
        return const Color(0xFF90CAF9).withValues(alpha: 0.05);
      case WeatherState.moderateRain:
        return const Color(0xFF5C85C8).withValues(alpha: 0.12);
      case WeatherState.heavyRain:
        return const Color(0xFF283593).withValues(alpha: 0.18);
      case WeatherState.typhoon:
        return const Color(
          0xFF1A237E,
        ).withValues(alpha: 0.24); // Lighter for visibility
    }
  }

  Color _dropColor(WeatherState s) {
    switch (s) {
      case WeatherState.clear:
      case WeatherState.partlyCloudy:
        return Colors.transparent;
      case WeatherState.typhoon:
        return const Color(0xFF5C72A6).withValues(alpha: 0.90);
      case WeatherState.heavyRain:
        return const Color(0xFF6B8BCC).withValues(alpha: 0.85);
      case WeatherState.moderateRain:
        return const Color(0xFF7A9FE6).withValues(alpha: 0.80);
      case WeatherState.lightRain:
        return const Color(0xFF8BAAF0).withValues(alpha: 0.75);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Nothing to render when clear and tint has faded
    final showBanner =
        _current == WeatherState.heavyRain || _current == WeatherState.typhoon;
    final showRain =
        _current != WeatherState.clear && _current != WeatherState.partlyCloudy;

    if (!showBanner && !showRain && _tintController.value == 0) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1 ── atmospheric tint (animated fade between states) ───────────────
          AnimatedBuilder(
            animation: _tintController,
            builder: (_, _) {
              final prev = _tintColor(_previous);
              final next = _tintColor(_current);
              final color =
                  Color.lerp(prev, next, _tintController.value) ?? next;
              if (color == Colors.transparent) return const SizedBox.shrink();
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: color.a * 0.7),
                      color,
                      color.withValues(alpha: color.a * 0.5),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          ),

          // 2 ── edge flood-glow pulse removed for usability ───────────────────

          // 3 ── rain particles (custom painter) ──────────────────────────────
          if (showRain && _drops.isNotEmpty)
            CustomPaint(
              painter: _RainPainter(
                drops: _drops,
                color: _dropColor(_current),
                angle: _dropAngle(_current),
                repaint: _rainController,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rain Painter
// ─────────────────────────────────────────────────────────────────────────────

class _RainPainter extends CustomPainter {
  final List<_RainDrop> drops;
  final Color color;
  final double angle;

  _RainPainter({
    required this.drops,
    required this.color,
    required this.angle,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (final d in drops) {
      // Vary length and opacity based on drop's speedVariance
      final len = 14.0 + (d.speedVariance * 12.0);
      final dropOpacity = color.a * (0.5 + 0.5 * d.speedVariance);

      paint.color = color.withValues(alpha: dropOpacity);
      paint.strokeWidth =
          1.2 + (d.speedVariance * 0.8); // Thicker drops so they are visible

      final x1 = d.x;
      final y1 = d.y;
      final x2 = x1 - len * angle;
      final y2 = y1 - len;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Rain drop data
// ─────────────────────────────────────────────────────────────────────────────

class _RainDrop {
  double x;
  double y;
  final double speedVariance; // 0.0 – 0.6

  _RainDrop({required this.x, required this.y, required this.speedVariance});

  factory _RainDrop.random(math.Random rng, Size size) => _RainDrop(
    x:
        rng.nextDouble() * (size.width + 600) -
        300, // Spawn wider to account for wind
    y: rng.nextDouble() * size.height,
    speedVariance: rng.nextDouble() * 0.6,
  );

  void reset(math.Random rng, Size size) {
    x =
        rng.nextDouble() * (size.width + 600) -
        300; // Spawn wider to account for wind
    y = -20;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Storm Warning Banner
// ─────────────────────────────────────────────────────────────────────────────

class StormBanner extends StatefulWidget {
  final WeatherState state;
  final VoidCallback? onClose;

  const StormBanner({super.key, required this.state, this.onClose});

  @override
  State<StormBanner> createState() => _StormBannerState();
}

class _StormBannerState extends State<StormBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTyphoon = widget.state == WeatherState.typhoon;
    final bg = isTyphoon ? const Color(0xFF4A148C) : const Color(0xFF0D47A1);
    final icon = isTyphoon
        ? Icons.cyclone_rounded
        : Icons.thunderstorm_outlined;
    final label = AppEnvironment.sparkCoreEnabled ? 'SEVERE WEATHER ESTIMATE' : isTyphoon ? 'TYPHOON ALERT' : 'HEAVY RAIN ALERT';
    final sub = isTyphoon
        ? 'Roads may be impassable. Seek safe shelter immediately.'
        : 'Flooding possible. Vulnerable roads may be auto-escalated.';

    return AnimatedBuilder(
      animation: _blink,
      builder: (_, _) {
        return Container(
          margin: const EdgeInsets.only(
            top: 8,
          ), // Replaced massive top margin since we pushed it down
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // blinking icon
              Opacity(
                opacity: 0.6 + (_blink.value * 0.4),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onClose != null)
                GestureDetector(
                  onTap: widget.onClose,
                  child: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
