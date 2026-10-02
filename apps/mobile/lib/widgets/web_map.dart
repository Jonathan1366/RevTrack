import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../core/fleet.dart';

@JS('revtrackCreateMap')
external void _create(
  JSString id,
  JSString token,
  JSString style,
  JSString data,
  JSString selected,
  JSFunction callback,
);
@JS('revtrackUpdateMap')
external void _update(
  JSString id,
  JSString data,
  JSString selected,
  JSBoolean reduceMotion,
);
@JS('revtrackDestroyMap')
external void _destroy(JSString id);

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
}) => _WebMap(
  vehicles: vehicles,
  selected: selected,
  onSelect: onSelect,
  token: token,
  style: style,
  pitch: pitch,
  route: route,
  destination: destination,
  focusSerial: focusSerial,
  traffic: traffic,
);

class _WebMap extends StatefulWidget {
  const _WebMap({
    required this.vehicles,
    required this.selected,
    required this.onSelect,
    required this.token,
    required this.style,
    required this.pitch,
    required this.route,
    required this.destination,
    required this.focusSerial,
    required this.traffic,
  });
  final List<Vehicle> vehicles;
  final Vehicle selected;
  final ValueChanged<Vehicle> onSelect;
  final String token, style;
  final double pitch;
  final List<List<double>> route;
  final List<double>? destination;
  final int focusSerial;
  final bool traffic;
  @override
  State<_WebMap> createState() => _WebMapState();
}

class _WebMapState extends State<_WebMap> {
  static int counter = 0;
  late final id = 'revtrack-map-${counter++}';
  bool initialized = false;
  String get data => jsonEncode({
    'style': widget.style,
    'pitch': widget.pitch,
    'route': widget.route,
    'destination': widget.destination,
    'focusSerial': widget.focusSerial,
    'traffic': widget.traffic,
    'vehicles': widget.vehicles
        .map(
          (v) => {
            'id': v.id,
            'plate': v.plate,
            'latitude': v.lat,
            'longitude': v.lng,
            'status': v.status,
            'ev': v.ev,
          },
        )
        .toList(),
  });
  @override
  void didUpdateWidget(covariant _WebMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (initialized) {
      _update(
        id.toJS,
        data.toJS,
        widget.selected.id.toJS,
        MediaQuery.disableAnimationsOf(context).toJS,
      );
    }
  }

  @override
  void dispose() {
    if (initialized) _destroy(id.toJS);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'div',
    onElementCreated: (element) {
      final host = element as web.HTMLDivElement;
      host.id = id;
      host.style.width = '100%';
      host.style.height = '100%';
      _create(
        id.toJS,
        widget.token.toJS,
        widget.style.toJS,
        data.toJS,
        widget.selected.id.toJS,
        ((JSString selectedId) {
          if (!mounted) return;
          for (final v in widget.vehicles) {
            if (v.id == selectedId.toDart) {
              widget.onSelect(v);
              break;
            }
          }
        }).toJS,
      );
      initialized = true;
    },
  );
}
