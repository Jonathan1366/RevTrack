import 'package:flutter/material.dart';

const ink = Color(0xFF14243D);
const muted = Color(0xFF62748A);
const green = Color(0xFF1764EE); // RevTrack primary electric blue.
const mint = Color(0xFFEBF2FF);
const lime = Color(0xFFB4D5FF);
const canvasColor = Color(0xFFF5F7FB);
const line = Color(0xFFE5EBF3);
const amber = Color(0xFFC88520);
const red = Color(0xFFC95D4F);

ThemeData revTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: canvasColor,
  colorScheme: ColorScheme.fromSeed(seedColor: green, surface: Colors.white),
  fontFamily: 'Inter',
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.3,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -.8,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w700,
      letterSpacing: -.6,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: ink),
    bodySmall: TextStyle(fontSize: 11, height: 1.4, color: muted),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: canvasColor,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    hintStyle: const TextStyle(fontSize: 12, color: muted),
  ),
  dividerTheme: const DividerThemeData(color: line, thickness: 1),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: green,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    ),
  ),
);

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    super.key,
    this.color = green,
    this.background = mint,
    this.icon,
  });
  final String text;
  final Color color, background;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Color statusColor(String status) => switch (status) {
  'moving' => green,
  'idle' => amber,
  'charging' => green,
  'parked' => amber,
  _ => muted,
};
