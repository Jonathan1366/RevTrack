import 'package:flutter/material.dart';
import '../core/design.dart';
import '../core/fleet.dart';

class CopilotPanel extends StatefulWidget {
  const CopilotPanel({
    super.key,
    required this.vehicles,
    required this.alerts,
    required this.onNavigate,
  });
  final List<Vehicle> vehicles;
  final List<FleetAlert> alerts;
  final ValueChanged<int> onNavigate;
  @override
  State<CopilotPanel> createState() => _CopilotPanelState();
}

class _CopilotPanelState extends State<CopilotPanel> {
  final controller = TextEditingController();
  String topic = 'koneksi';
  String? queryError;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void choose(String text) {
    final query = text.trim().toLowerCase();
    if (query.isEmpty) return;
    setState(() {
      queryError = null;
      if (RegExp(r'energi|baterai|bensin|bahan bakar').hasMatch(query)) {
        topic = 'energi';
      } else if (RegExp(r'pengemudi|driver|penugasan|tugas').hasMatch(query)) {
        topic = 'pengemudi';
      } else if (RegExp(
        r'koneksi|offline|prioritas|peringatan',
      ).hasMatch(query)) {
        topic = 'koneksi';
      } else {
        queryError =
            'Pilih koneksi, energi, atau pengemudi untuk melihat ringkasannya.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final offline = widget.vehicles
        .where((v) => v.status == 'offline')
        .toList();
    final low = widget.vehicles
        .where((v) => v.energy != null && v.energy! < 30)
        .toList();
    final unknown = widget.vehicles.where((v) => v.energy == null).length;
    final relevant = topic == 'energi'
        ? low
        : topic == 'pengemudi'
        ? widget.vehicles
        : offline;
    final title = switch (topic) {
      'energi' => 'Energi kendaraan',
      'pengemudi' => 'Penugasan pengemudi',
      _ => 'Koneksi kendaraan',
    };
    final answer = switch (topic) {
      'energi' =>
        '${low.length} kendaraan memiliki energi di bawah 30%. Periksa rencana perjalanan sebelum mengisi ulang.${unknown > 0 ? ' Data energi belum tersedia untuk $unknown kendaraan.' : ''}',
      'pengemudi' =>
        'Periksa penugasan pada ${widget.vehicles.length} kendaraan. Buka detail kendaraan untuk mengganti pengemudi.',
      _ =>
        '${offline.length} kendaraan sedang offline. Periksa laporan terakhir dan hubungi pengemudinya bila perlu.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'REV RENTAL · JAKARTA',
          style: TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Text(
          'Analisis armada',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Ringkasan koneksi, energi, dan penugasan kendaraan.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey('copilot-input'),
          controller: controller,
          onSubmitted: choose,
          decoration: InputDecoration(
            hintText: 'Cari topik analisis',
            prefixIcon: const Icon(Icons.search_rounded),
            errorText: queryError,
            errorMaxLines: 2,
            suffixIcon: IconButton(
              tooltip: 'Cari topik',
              onPressed: () => choose(controller.text),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in [
              ('koneksi', 'Koneksi'),
              ('energi', 'Energi'),
              ('pengemudi', 'Pengemudi'),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: topic == item.$1,
                onSelected: (_) => choose(item.$1),
              ),
          ],
        ),
        const SizedBox(height: 28),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: Surface(
            key: ValueKey(topic),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      topic == 'energi'
                          ? Icons.battery_5_bar_outlined
                          : topic == 'pengemudi'
                          ? Icons.people_outline
                          : Icons.sensors_off_rounded,
                      color: green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(answer, style: const TextStyle(height: 1.7)),
                const SizedBox(height: 20),
                for (final v in relevant.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.plate,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                v.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: Text(
                            topic == 'energi'
                                ? '${v.energy}%'
                                : topic == 'pengemudi'
                                ? v.driver
                                : v.statusLabel,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      widget.onNavigate(topic == 'koneksi' ? 2 : 1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    topic == 'koneksi' ? 'Tinjau peringatan' : 'Lihat armada',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Ringkasan dihitung dari data armada dengan aturan sederhana. Data mode demo merupakan simulasi.',
          style: TextStyle(fontSize: 12, color: muted, height: 1.6),
        ),
      ],
    );
  }
}
