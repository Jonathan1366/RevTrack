import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/design.dart';
import '../core/fleet.dart';
import 'fleet_map.dart';
import 'glass_surface.dart';
import 'vehicle_card.dart';

class FleetOverview extends StatelessWidget {
  const FleetOverview({
    super.key,
    required this.vehicles,
    required this.selected,
    required this.openAlerts,
    required this.onSelect,
    required this.onDetail,
    required this.onMap,
    required this.onAlerts,
    required this.onFleet,
    required this.onFleetFilter,
  });

  final List<Vehicle> vehicles;
  final Vehicle selected;
  final int openAlerts;
  final ValueChanged<Vehicle> onSelect;
  final VoidCallback onDetail, onMap, onAlerts, onFleet;
  final ValueChanged<String> onFleetFilter;

  @override
  Widget build(BuildContext context) {
    final moving = vehicles.where((v) => v.status == 'moving').length;
    final offline = vehicles.where((v) => v.status == 'offline').length;
    final lowEnergy = vehicles
        .where((v) => v.energy != null && v.energy! < 30)
        .length;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rev Rental · Jakarta', style: TextStyle(color: muted)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Ringkasan armada',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              tooltip: 'Tinjau peringatan',
              onPressed: onAlerts,
              icon: Badge(
                isLabelVisible: openAlerts > 0,
                label: Text('$openAlerts'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF45416E), Color(0xFF161A36), Color(0xFF273854)],
            ),
          ),
          child: GlassSurface(
            dark: true,
            refract: false,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status armada',
                  style: TextStyle(color: Color(0xFFC5C5DC), fontSize: 13),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (final item in [
                      ('Total unit', vehicles.length, Colors.white),
                      ('Berjalan', moving, const Color(0xFF93E1C4)),
                      ('Offline', offline, const Color(0xFFFFBAC0)),
                    ])
                      Expanded(
                        child: InkWell(
                          key: ValueKey('fleet-stat-${item.$1}'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onFleetFilter(
                            item.$1 == 'Total unit' ? 'Semua' : item.$1,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.$2}',
                                style: numericStyle.copyWith(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                  color: item.$3,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.$1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFC5C5DC),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFF36384F)),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: onFleet,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('Lihat armada'),
                  ),
                ),
              ],
            ),
          ),
        ).animate(effects: reducedMotion ? [] : [FadeEffect(duration: 240.ms)]),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Posisi kendaraan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('open-map'),
              onPressed: onMap,
              icon: const Icon(Icons.open_in_full_rounded, size: 16),
              label: const Text('Buka peta', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 250,
            child: FleetMap(
              vehicles: vehicles,
              selected: selected,
              onSelect: onSelect,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Surface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selected.plate,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.circle,
                    size: 7,
                    color: statusColor(selected.status),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selected.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor(selected.status),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(selected.name, style: const TextStyle(color: muted)),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _reading(
                      Icons.speed_outlined,
                      '${selected.speed ?? '—'}',
                      'km/jam',
                    ),
                  ),
                  Column(
                    children: [
                      EnergyDial(value: selected.energy?.toDouble()),
                      Text(
                        selected.ev ? 'Baterai' : 'Bahan bakar',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Semantics(
                label: selected.energy == null
                    ? 'Data energi belum tersedia'
                    : '${selected.ev ? 'Baterai' : 'Bahan bakar'} ${selected.energy} persen',
                child: LinearProgressIndicator(
                  value: selected.energy == null
                      ? 0
                      : (selected.energy! / 100).clamp(0, 1),
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(5),
                  backgroundColor: line,
                  color: selected.energy != null && selected.energy! < 30
                      ? amber
                      : success,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onDetail,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Detail kendaraan'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: onAlerts,
            leading: const Icon(
              Icons.notification_important_outlined,
              color: amber,
            ),
            title: Text(
              openAlerts == 0
                  ? 'Semua peringatan sudah ditinjau'
                  : '$openAlerts peringatan belum ditinjau',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Periksa kejadian dan catatan kendaraan.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
        const SizedBox(height: 16),
        if (lowEnergy > 0)
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => onFleetFilter('Energi rendah'),
              leading: const Icon(Icons.battery_alert_outlined, color: amber),
              title: Text(
                '$lowEnergy kendaraan dengan energi rendah',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Energi di bawah 30%. Periksa rencana perjalanan.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Mode demo · posisi dan telemetri merupakan simulasi.',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }

  Widget _reading(IconData icon, String value, String label) => Row(
    children: [
      Icon(icon, color: muted, size: 22),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: numericStyle.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    ],
  );
}
