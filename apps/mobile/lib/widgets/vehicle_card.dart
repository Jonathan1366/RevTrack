import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/design.dart';
import '../core/fleet.dart';
import 'glass_surface.dart';

class FleetVehicleCard extends StatelessWidget {
  const FleetVehicleCard({
    super.key,
    required this.vehicle,
    required this.onTap,
    this.selected = false,
  });
  final Vehicle vehicle;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    return GlassSurface(
      radius: 26,
      refract: false,
      tint: selected ? const Color(0xFFF1EBFF) : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .65),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white),
                      ),
                      child: Icon(
                        v.ev
                            ? Icons.electric_car_rounded
                            : Icons.directions_car_rounded,
                        color: green,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.plate,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: -.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            v.name,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.north_east_rounded,
                      size: 18,
                      color: muted,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.circle, color: statusColor(v.status), size: 7),
                    const SizedBox(width: 6),
                    Text(
                      v.statusLabel,
                      style: TextStyle(
                        color: statusColor(v.status),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      v.energyLabel,
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    EnergyDial(value: v.energy?.toDouble(), size: 74),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${v.speed ?? '—'}',
                            style: numericStyle.copyWith(
                              color: ink,
                              fontSize: 30,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1,
                            ),
                          ),
                          const Text(
                            'km/jam',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.range == null ? '—' : '${v.range}',
                            style: numericStyle.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Text(
                            'km estimasi',
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 16,
                      color: muted,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        v.driver,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: muted,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        v.location,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bounded 0–100% instrument; missing readings are never shown as zero.
class EnergyDial extends StatelessWidget {
  const EnergyDial({super.key, required this.value, this.size = 88});
  final double? value;
  final double size;
  @override
  Widget build(BuildContext context) {
    final valid =
        value != null && value!.isFinite && value! >= 0 && value! <= 100;
    final color = !valid
        ? muted
        : value! < 30
        ? amber
        : green;
    return Semantics(
      label: valid
          ? 'Energi ${value!.round()} persen'
          : 'Energi belum tersedia',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: valid ? value! / 100 : 0,
              end: valid ? value! / 100 : 0,
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => CustomPaint(
              painter: _EnergyRing(progress, color),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          valid ? '${value!.round()}%' : '—',
                          style: numericStyle.copyWith(
                            fontSize: size * .23,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        Text(
                          'Energi',
                          style: TextStyle(fontSize: size * .12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnergyRing extends CustomPainter {
  const _EnergyRing(this.progress, this.color);
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(4);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      math.pi * .75,
      math.pi * 1.5,
      false,
      base..color = line,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        math.pi * .75,
        math.pi * 1.5 * progress,
        false,
        base
          ..shader = SweepGradient(
            startAngle: math.pi * .75,
            endAngle: math.pi * 2.25,
            colors: [color.withValues(alpha: .5), color],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EnergyRing oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
