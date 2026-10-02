import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/design.dart';

enum ActionPhase { ready, busy, complete }

/// The caller owns the request; completion is shown only after it succeeds.
class ActionFeedbackButton extends StatelessWidget {
  const ActionFeedbackButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.phase = ActionPhase.ready,
    this.completedLabel = 'Tersimpan',
    this.destructive = false,
    this.busyLabel = 'Memproses…',
  });
  final String label, completedLabel;
  final String busyLabel;
  final VoidCallback? onPressed;
  final ActionPhase phase;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final complete = phase == ActionPhase.complete;
    return OutlinedButton(
      onPressed: phase == ActionPhase.ready ? onPressed : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive ? red : green,
        disabledForegroundColor: complete ? success : muted,
        backgroundColor: complete ? const Color(0xFFEDF7F2) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: phase == ActionPhase.busy
                ? const SizedBox(
                    key: ValueKey('busy'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    complete
                        ? Icons.check_circle_outline_rounded
                        : destructive
                        ? Icons.delete_outline_rounded
                        : Icons.arrow_forward_rounded,
                    key: ValueKey(phase),
                    size: 18,
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            complete
                ? completedLabel
                : phase == ActionPhase.busy
                ? busyLabel
                : label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class FleetLoading extends StatelessWidget {
  const FleetLoading({super.key});
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    Widget skeleton(double height, {double? width}) {
      final shape = Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: line,
          borderRadius: BorderRadius.circular(12),
        ),
      );
      return reduced
          ? shape
          : shape
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(
                  duration: 1400.ms,
                  color: Colors.white.withValues(alpha: .7),
                );
    }

    return Semantics(
      label: 'Memuat data armada',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Memuat armada…', style: TextStyle(color: muted)),
          const SizedBox(height: 18),
          skeleton(28, width: 220),
          const SizedBox(height: 24),
          skeleton(180),
          const SizedBox(height: 24),
          skeleton(250),
          const SizedBox(height: 16),
          skeleton(90),
        ],
      ),
    );
  }
}

void showOutcome(BuildContext context, String message, {bool failed = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Icon(
              failed
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: failed ? const Color(0xFFFFBAC0) : const Color(0xFF93E1C4),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
      showCloseIcon: true,
    ),
  );
}
