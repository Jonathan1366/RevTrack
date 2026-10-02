import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Decorative motion is bounded and respects the device's reduced-motion setting.
class IntelligenceOrb extends StatefulWidget {
  const IntelligenceOrb({super.key, this.size = 64});
  final double size;
  @override
  State<IntelligenceOrb> createState() => _IntelligenceOrbState();
}

class _IntelligenceOrbState extends State<IntelligenceOrb>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
    } else {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, child) => CustomPaint(
        size: Size.square(widget.size),
        painter: _OrbPainter(controller.value),
      ),
    ),
  );
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter(this.phase);
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * .37;
    canvas.drawCircle(
      center,
      radius * 1.2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF2780FF).withValues(alpha: .20),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(phase * math.pi * 2);
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2,
        height: radius * 1.6,
      );
      canvas.rotate(math.pi / 3);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = SweepGradient(
            colors: [
              const Color(0xFF5BBFFF).withValues(alpha: .85),
              const Color(0xFF285BF7).withValues(alpha: .9),
              const Color(0xFFABA6FF).withValues(alpha: .75),
              const Color(0xFF5BBFFF).withValues(alpha: .85),
            ],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * .20,
      );
    }
    canvas.restore();
    canvas.drawCircle(
      center,
      radius * .55,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.4, -.4),
          colors: [Colors.white, Color(0xFFBFDFFF), Color(0xFF4F81F6)],
        ).createShader(Rect.fromCircle(center: center, radius: radius * .6)),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.phase != phase;
}
