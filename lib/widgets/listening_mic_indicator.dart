import 'package:flutter/material.dart';

/// Wavy mic + "listening..." indicator. Animation (rings expanding, mic
/// bouncing, text pulsing) only runs while [isListening] is true — when
/// false, it settles into a static resting state.
class ListeningMicIndicator extends StatefulWidget {
  const ListeningMicIndicator({
    super.key,
    required this.isListening,
    this.label = 'listening...',
    this.color = const Color(0xFF6C8EF5),
  });

  final bool isListening;
  final String label;
  final Color color;

  @override
  State<ListeningMicIndicator> createState() => _ListeningMicIndicatorState();
}

class _ListeningMicIndicatorState extends State<ListeningMicIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.isListening) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ListeningMicIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _controller.repeat();
    } else if (!widget.isListening && oldWidget.isListening) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value; // 0..1, looping
        final micScale = widget.isListening
            ? 1.0 + 0.06 * _bounceCurve(t)
            : 1.0;
        final textOpacity = widget.isListening
            ? 0.55 + 0.45 * _bounceCurve(t)
            : 1.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: textOpacity,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 18,
                  color: widget.color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 180,
              height: 180,
              child: CustomPaint(
                painter: widget.isListening
                    ? _SoundRingsPainter(progress: t, color: widget.color)
                    : null,
                child: Center(
                  child: Transform.scale(
                    scale: micScale,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.color.withValues(alpha: 0.9),
                            widget.color.withValues(alpha: 0.6),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.35),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Smooth 0->1->0 pulse from a 0..1 looping value.
  double _bounceCurve(double t) => (1 - (2 * t - 1).abs());
}

/// Draws 3 concentric rings expanding outward and fading, staggered in
/// phase so they don't all pulse in lockstep.
class _SoundRingsPainter extends CustomPainter {
  _SoundRingsPainter({required this.progress, required this.color});

  final double progress; // 0..1 looping
  final Color color;

  static const _ringCount = 3;
  static const _minRadius = 40.0;
  static const _maxRadius = 88.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (var i = 0; i < _ringCount; i++) {
      final phase = (progress + i / _ringCount) % 1.0;
      final radius = _minRadius + (_maxRadius - _minRadius) * phase;
      final opacity = (1 - phase).clamp(0.0, 1.0) * 0.5;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoundRingsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
