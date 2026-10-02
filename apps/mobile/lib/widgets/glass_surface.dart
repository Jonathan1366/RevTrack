import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Bounded glass surfaces keep readable content above the effect. Refraction is
/// restricted to navigation and controls; web and unsupported GPUs use SDK blur.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.dark = false,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.refract = true,
    this.tint,
  });
  final Widget child;
  final bool dark;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool refract;
  final Color? tint;
  // The experimental renderer duplicated screen regions on our Android GLES
  // emulator. Keep the verified blur path as default; opt in on tested GPUs.
  static const refractive = bool.fromEnvironment('ENABLE_REFRACTIVE_GLASS');

  @override
  Widget build(BuildContext context) {
    final solid = MediaQuery.highContrastOf(context);
    final content = Padding(padding: padding, child: child);
    final borderRadius = BorderRadius.circular(radius);
    final decoration = BoxDecoration(
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: solid
            ? [
                dark ? const Color(0xFF16192E) : Colors.white,
                dark ? const Color(0xFF16192E) : Colors.white,
              ]
            : dark
            ? [const Color(0xD02B2D42), const Color(0xB316192E)]
            : [
                tint?.withValues(alpha: .88) ?? const Color(0xD9FFFFFF),
                tint?.withValues(alpha: .68) ?? const Color(0xAFEDEAF8),
              ],
      ),
      border: Border.all(color: dark ? Colors.white24 : Colors.white, width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1808091F),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    );
    final supported =
        !kIsWeb &&
        [
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform);
    if (refractive &&
        refract &&
        supported &&
        ImageFilter.isShaderFilterSupported &&
        !solid &&
        !MediaQuery.disableAnimationsOf(context)) {
      return LiquidGlass.withOwnLayer(
        settings: LiquidGlassSettings(
          thickness: 12,
          blur: 8,
          glassColor: dark ? const Color(0xBB16192E) : const Color(0xCCFFFFFF),
          lightIntensity: 1.2,
          saturation: 1.1,
        ),
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        child: content,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: decoration.boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: solid ? 0 : 12,
            sigmaY: solid ? 0 : 12,
          ),
          child: DecoratedBox(decoration: decoration, child: content),
        ),
      ),
    );
  }
}

/// Static color fields give the glass depth without running a background
/// animation behind live telemetry or increasing idle battery usage.
class FleetBackdrop extends StatelessWidget {
  const FleetBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE8E2F9), Color(0xFFF4F4FA), Color(0xFFE4F0F3)],
      ),
    ),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.9, -.6),
          radius: 1.2,
          colors: [Color(0x66C3DCEB), Color(0x00FFFFFF)],
        ),
      ),
      child: child,
    ),
  );
}

class GlassAction extends StatefulWidget {
  const GlassAction({
    super.key,
    required this.child,
    required this.onPressed,
    this.dark = true,
    this.label,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool dark;
  final String? label;
  @override
  State<GlassAction> createState() => _GlassActionState();
}

class _GlassActionState extends State<GlassAction> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed ? .96 : 1,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120),
    child: GlassSurface(
      dark: widget.dark,
      radius: 24,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onHighlightChanged: (value) => setState(() => pressed = value),
          borderRadius: BorderRadius.circular(24),
          child: Semantics(
            button: true,
            label: widget.label,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: widget.child,
            ),
          ),
        ),
      ),
    ),
  );
}
