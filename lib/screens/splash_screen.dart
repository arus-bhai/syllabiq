import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../repositories/syllabus_repository.dart';
import 'syllabus_list_screen.dart';
import '../repositories/syllabus_repository.dart';
import 'grade_select_screen.dart';

/// Brand palette from the design spec.
class SyllabiqColors {
  static const paper = Color(0xFFF7F5F1);
  static const graphite = Color(0xFF1C1B19);
  static const graphiteDark = Color(0xFF141513);
  static const teal = Color(0xFF00C2A8);
  static const tealDeep = Color(0xFF00776A);
  static const barGradientTop = Color(0xFF2BE7CD);
  static const barGradientBottom = Color(0xFF00A892);
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.repository});

  final SyllabusRepository repository;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // One-shot entrance choreography: bars scale in, rise, wordmark lifts.
  late final AnimationController _entrance;
  // Continuous loop: pulse ring + loading dots, held until navigation.
  late final AnimationController _loop;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..forward();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    Future.delayed(const Duration(milliseconds: 3000), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GradeSelectScreen(repository: widget.repository),
        ),
      );
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final bg = isDark ? SyllabiqColors.graphiteDark : SyllabiqColors.paper;
    final fg = isDark ? SyllabiqColors.paper : SyllabiqColors.graphite;

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WaveformMark(entrance: _entrance, loop: _loop),
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) {
                final t = _clampedInterval(_entrance.value, 0.70, 1.0);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 14),
                    child: child,
                  ),
                );
              },
              child: Text(
                'Syllabiq',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(height: 40),
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) {
                final t = _clampedInterval(_entrance.value, 0.88, 1.0);
                return Opacity(opacity: t, child: child);
              },
              child: AnimatedBuilder(
                animation: _loop,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) {
                      final phase = (_loop.value * 1800 / 1100 + i * 0.18) % 1.0;
                      final opacity = 0.25 + 0.75 * _triangle(phase);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3.5),
                        child: Opacity(
                          opacity: opacity,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: SyllabiqColors.teal,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _clampedInterval(double v, double start, double end) {
    if (v <= start) return 0;
    if (v >= end) return 1;
    return (v - start) / (end - start);
  }

  static double _triangle(double t) => 1 - (2 * t - 1).abs();
}

class _WaveformMark extends StatelessWidget {
  const _WaveformMark({required this.entrance, required this.loop});

  final AnimationController entrance;
  final AnimationController loop;

  static const _maxBarHeight = 64.0;
  static const _barHeights = [0.33, 0.67, 1.0, 0.60, 0.29];
  static const _barDelays = [0.0, 0.08, 0.16, 0.24, 0.32];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([entrance, loop]),
      builder: (context, _) {
        // Container scale-in: 0.82 -> 1.03 -> 1.0 over the first ~45%.
        final scaleT = _SplashScreenState._clampedInterval(entrance.value, 0, 0.45);
        final containerScale = 0.82 + 0.21 * Curves.easeOutBack.transform(scaleT);

        // Pulse ring, continuous loop, scale 0.7 -> 1.9 fading out.
        final ringT = loop.value;
        final ringScale = 0.7 + 1.2 * ringT;
        final ringOpacity = (0.55 * (1 - ringT)).clamp(0.0, 1.0);

        return SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: SyllabiqColors.teal.withValues(alpha: ringOpacity),
                      width: 1,
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: containerScale,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(5, (i) {
                    // Per-bar rise: scaleY 0.06 -> 1.0 -> 0.45 -> settles 0.78.
                    final barStart = 0.30 + _barDelays[i];
                    final barT = _SplashScreenState._clampedInterval(
                      entrance.value,
                      barStart,
                      (barStart + 0.35).clamp(0.0, 1.0),
                    );
                    final settleT = _SplashScreenState._clampedInterval(
                      entrance.value,
                      barStart + 0.35,
                      1.0,
                    );
                    double riseScale;
                    if (barT < 1.0) {
                      riseScale = 0.06 + 0.94 * Curves.easeOut.transform(barT);
                    } else {
                      riseScale = 1.0 + (0.78 - 1.0) * settleT;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5.5),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: 1,
                        child: Transform(
                          alignment: Alignment.bottomCenter,
                          transform: Matrix4.diagonal3Values(1, riseScale, 1),
                          child: Container(
                            width: 12,
                            height: _maxBarHeight * _barHeights[i],
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  SyllabiqColors.barGradientTop,
                                  SyllabiqColors.barGradientBottom,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
