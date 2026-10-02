import 'package:flutter/material.dart';
import '../core/design.dart';
import '../core/fleet.dart';
import 'operations.dart';
import 'csv_export_stub.dart'
    if (dart.library.js_interop) 'csv_export_web.dart'
    as exporter;

class ReportsPanel extends StatefulWidget {
  const ReportsPanel({super.key});
  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel> {
  Map<String, dynamic>? report;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final result = await const FleetApi().request('/v1/reports/summary');
      if (mounted) setState(() => report = result);
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    }
  }

  Future<void> export() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final csv = await const FleetApi().csv();
      await exporter.exportCsv(csv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exporter.downloadsFile
                  ? 'Laporan CSV diunduh.'
                  : 'Laporan CSV disalin. Tempel ke file atau spreadsheet.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(readableError(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error!, style: const TextStyle(color: red)),
            TextButton(onPressed: load, child: const Text('Coba lagi')),
          ],
        ),
      );
    }
    if (report == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final rental = report!['rental'] as Map;
    final maintenance = report!['maintenance'] as Map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Surface(
          color: mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Laporan yang bisa ditelusuri.',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                '${report!['telemetrySamples']} sampel tersimpan · diperbarui ${shortTime(report!['generatedAt'])}',
                style: const TextStyle(color: green, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cakupan laporan mengikuti sampel yang tersimpan. Riwayat demo dibatasi 500 sampel per unit; angka ini bukan total perjalanan atau konsumsi energi terverifikasi.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.7),
              ),
              const SizedBox(height: 17),
              FilledButton.icon(
                onPressed: busy ? null : export,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(
                  busy
                      ? 'Menyiapkan…'
                      : exporter.downloadsFile
                      ? 'Unduh CSV telemetri'
                      : 'Salin CSV telemetri',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in [
              ('Rental aktif', rental['active']),
              ('Booking mendatang', rental['upcoming']),
              ('Lewat waktu', rental['overdue']),
              ('Sudah kembali', rental['returned']),
              ('Servis terbuka', maintenance['open']),
              ('Servis selesai', maintenance['completed']),
            ])
              SizedBox(
                width: 150,
                child: Surface(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${item.$2}',
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        for (final unit in report!['vehicles'] as List)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Surface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          unit['plate'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Tag('${unit['samples']} sampel'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Kecepatan maksimum tersimpan: ${unit['maxObservedSpeedKph'] ?? '—'} km/jam',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${unit['energyKind'] == 'battery' ? 'Baterai' : 'BBM'}: ${unit['firstEnergyPercent'] ?? '—'}% → ${unit['lastEnergyPercent'] ?? '—'}% · fixture ${unit['fixtureSamples']} / simulator ${unit['simulatorSamples']}',
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
