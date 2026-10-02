import 'package:flutter/material.dart';
import '../core/fleet.dart';

Widget buildWebMap({
  required List<Vehicle> vehicles,
  required Vehicle selected,
  required ValueChanged<Vehicle> onSelect,
  required String token,
  required String style,
  double pitch = 36,
  List<List<double>> route = const [],
  List<double>? destination,
  int focusSerial = 0,
  bool traffic = false,
}) => const SizedBox.shrink();
