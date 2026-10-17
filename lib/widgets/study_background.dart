import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Full-screen gradient background with faint scattered doodle-style study
/// icons (assets/icons/*.svg), matching the reference "listening" screen.
/// Wrap a screen's body in this.
class StudyBackground extends StatelessWidget {
  const StudyBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8FD3C8), Color(0xFF8FA8E8)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _ScatteredIcons()),
          child,
        ],
      ),
    );
  }
}

class _IconPlacement {
  const _IconPlacement(this.asset, this.dx, this.dy, this.size, this.rotation);
  final String asset; // path under assets/icons/
  final double dx; // fractional x position (0..1)
  final double dy; // fractional y position (0..1)
  final double size;
  final double rotation; // radians
}

class _ScatteredIcons extends StatelessWidget {
  const _ScatteredIcons();

  static const _iconOpacity = 0.18;

  static final _placements = <_IconPlacement>[
    _IconPlacement('assets/icons/book.svg', 0.06, 0.05, 36, -0.15),
    _IconPlacement('assets/icons/clock.svg', 0.42, 0.02, 30, 0.1),
    _IconPlacement('assets/icons/lightbulb.svg', 0.78, 0.05, 32, 0.0),
    _IconPlacement('assets/icons/globe.svg', 0.88, 0.26, 42, 0.0),
    _IconPlacement('assets/icons/book.svg', 0.04, 0.22, 26, 0.2),
    _IconPlacement('assets/icons/paperplane.svg', 0.62, 0.16, 32, -0.4),
    _IconPlacement('assets/icons/apple.svg', 0.66, 0.02, 24, 0.0),
    _IconPlacement('assets/icons/clock.svg', 0.08, 0.55, 30, 0.0),
    _IconPlacement('assets/icons/magnifier.svg', 0.12, 0.68, 28, -0.1),
    _IconPlacement('assets/icons/flask.svg', 0.84, 0.66, 34, 0.0),
    _IconPlacement('assets/icons/pencil.svg', 0.88, 0.84, 30, 0.3),
    _IconPlacement('assets/icons/book.svg', 0.05, 0.88, 32, 0.0),
    _IconPlacement('assets/icons/star.svg', 0.92, 0.46, 22, 0.0),
    _IconPlacement('assets/icons/star.svg', 0.86, 0.92, 20, 0.0),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (final p in _placements)
              Positioned(
                left: constraints.maxWidth * p.dx,
                top: constraints.maxHeight * p.dy,
                child: Transform.rotate(
                  angle: p.rotation,
                  child: SvgPicture.asset(
                    p.asset,
                    width: p.size,
                    height: p.size,
                    colorFilter: ColorFilter.mode(
                      Colors.white.withValues(alpha: _iconOpacity),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
