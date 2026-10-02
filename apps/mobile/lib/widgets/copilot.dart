import 'package:flutter/material.dart';
import '../core/design.dart';
import '../core/fleet.dart';
import 'intelligence_orb.dart';

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
  String topic = 'prioritas';
  bool thinking = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> ask(String text) async {
    if (text.trim().isEmpty || thinking) return;
    setState(() => thinking = true);
    await Future<void>.delayed(
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
    );
    if (mounted) {
      setState(() {
        topic = text.toLowerCase();
        thinking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final energy =
        topic.contains('energi') ||
        topic.contains('baterai') ||
        topic.contains('bensin');
    final driver =
        topic.contains('driver') ||
        topic.contains('pengemudi') ||
        topic.contains('tugas');
    final offline = widget.vehicles
        .where((v) => v.status == 'offline')
        .toList();
    final low = widget.vehicles
        .where((v) => v.energy != null && v.energy! < 30)
        .toList();
    final unknown = widget.vehicles.where((v) => v.energy == null).length;
    final open = widget.alerts
        .where((a) => a.status != 'acknowledged')
        .toList();
    final relevant = energy
        ? low
        : driver
        ? widget.vehicles
        : offline;
    final answer = energy
        ? '${low.length} unit memiliki energi di bawah 30%. $unknown unit belum memiliki data energi. Periksa kebutuhan perjalanan berikutnya sebelum merencanakan pengisian.'
        : driver
        ? '${widget.vehicles.length} unit mempunyai profil penugasan pada snapshot ini. Buka detail unit untuk mengganti pengemudi; server akan memeriksa bentrok penugasan.'
        : '${offline.length} unit offline dan ${open.length} peringatan belum ditinjau. Prioritaskan verifikasi koneksi, lalu tindak lanjuti kejadian berdasarkan bukti. Kehilangan sinyal sendiri tidak membuktikan pencurian.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'REV INTELLIGENCE',
          style: TextStyle(
            color: green,
            fontSize: 10,
            letterSpacing: 1.7,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Lebih jernih melihat.\nLebih yakin bertindak.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Asisten operasional berbasis data workspace. Anda tetap memegang keputusan.',
          style: TextStyle(color: muted, height: 1.6),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF122444), Color(0xFF1C3D6C)],
            ),
            boxShadow: [
              BoxShadow(
                color: green.withValues(alpha: .12),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  IntelligenceOrb(size: 68),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rev AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Analisis aturan · bukan model generatif',
                          style: TextStyle(
                            color: Color(0xFFB4CCE9),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('copilot-input'),
                controller: controller,
                onSubmitted: ask,
                decoration: InputDecoration(
                  hintText: 'Tanya prioritas, energi, atau pengemudi…',
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    onPressed: thinking ? null : () => ask(controller.text),
                    icon: const Icon(Icons.arrow_upward_rounded, color: green),
                    tooltip: 'Analisis pertanyaan',
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final prompt in [
                    'Prioritas hari ini',
                    'Cek energi armada',
                    'Tinjau pengemudi',
                  ])
                    ActionChip(
                      label: Text(prompt, style: const TextStyle(fontSize: 11)),
                      onPressed: () => ask(prompt),
                      backgroundColor: const Color(0xFFECF3FF),
                      side: BorderSide.none,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: thinking
              ? const Surface(
                  key: ValueKey('thinking'),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 16),
                      Text('Menyusun data pendukung…'),
                    ],
                  ),
                )
              : Surface(
                  key: ValueKey(topic),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insights_rounded, color: green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              energy
                                  ? 'Kesiapan energi'
                                  : driver
                                  ? 'Penugasan pengemudi'
                                  : 'Urutan perhatian Anda',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Tag('TERUKUR'),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        answer,
                        style: const TextStyle(height: 1.8, fontSize: 14),
                      ),
                      const SizedBox(height: 18),
                      for (final v in relevant.take(5))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.subdirectory_arrow_right,
                                color: muted,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${v.plate} · ${energy
                                      ? '${v.energy}%'
                                      : driver
                                      ? v.driver
                                      : v.statusLabel}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(),
                      const SizedBox(height: 10),
                      const Text(
                        'Sumber: snapshot armada dan alert workspace demo. Tidak ada perintah yang dikirim ke kendaraan.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () =>
                            widget.onNavigate(energy || driver ? 1 : 2),
                        icon: const Icon(Icons.arrow_forward, size: 17),
                        label: const Text('Tinjau data dan ambil tindakan'),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Integrasi model AI, agent workflow, dan evaluasi produksi dijelaskan dalam blueprint. Analisis saat ini dihitung dengan aturan deterministik.',
          style: TextStyle(fontSize: 11, color: muted, height: 1.7),
        ),
      ],
    );
  }
}
