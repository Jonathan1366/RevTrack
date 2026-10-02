# Persiapan pilot dan backlog RevTrack

Rencana awal 2 Oktober 2026. Jumlah unit, biaya, jadwal dan target berikut perlu disepakati setelah inventaris kendaraan serta pengadaan. Kode starter belum memenuhi gerbang produksi di dokumen ini.

## 1. Paket persiapan bisnis

| Artefak | Isi yang harus dikumpulkan | Owner |
|---|---|---|
| Asset inventory | Nopol, model/tahun/varian, powertrain, cabang, kepemilikan, garansi, kondisi | Fleet owner |
| Operations map | Rental lepas kunci/driver, booking, deposit, handover, service, insiden | Product + operations |
| Risk register | Kerugian nyata, frekuensi fraud, prioritas risiko, biaya false alarm | Operations + security |
| Compatibility sheet | SKU tracker, firmware, sensor, CAN capability dan hasil bench | IoT lead |
| RFQ | Hardware, SIM, instalasi, spare, support, RMA, sertifikasi | Procurement + IoT |
| Data policy | Tujuan data, peran, retensi, voice, audit dan customer export | Legal/privacy + product |
| Unit economics | Capex, monthly COGS, harga usulan, margin, break-even | Finance |
| Incident SOP | Owner shift, escalation, verifikasi, recovery, komunikasi | Operations |

Mulai dari 3–5 kendaraan bench yang mewakili variasi, kemudian subset 20–30 unit untuk uji lapangan; dapat diperluas menjadi pilot 20–50 unit sesuai asumsi README. Jangan memasang sekaligus seluruh armada sebelum compatibility dan sleep current terbukti.

## 2. Backlog engineering

### Milestone A — data yang dapat dipercaya

- Provisioning device unik, install/uninstall history dan credential lifecycle.
- Rust protocol adapter satu vendor dengan official sample fixtures, checksum/length checks, bounded queue, reconnect/backfill.
- Go registry API, normalized contract, raw archive, idempotency, time/quality handling.
- PostgreSQL/PostGIS migration, non-owner role, transaction-scoped tenant context, negative isolation tests.
- Flutter Mapbox native, device-driven marker, last seen, unknown fields, stale/offline screen.
- Metrics ingest lag, parser reject, SIM/device online, power, buffer recovery dan cardinality budget.

**Lulus:** posisi bisa dicocokkan dengan ground truth, putus jaringan dapat dipulihkan, identitas device tidak dapat dipindah lewat payload, data lama tidak menimpa latest state.

### Milestone B — operasi rental

- OIDC/MFA, peran cabang, onboarding tenant.
- Booking/availability, driver assignment constraints, inspeksi, contract/return.
- Trip state machine, geofence polygon/rules, overspeed event dengan threshold konfigurasi.
- Inbox kasus, acknowledgement, escalation, supervisor dashboard.
- Service schedule dan energy capability per unit.

**Lulus:** operator menjalankan satu siklus rental nyata, mengoreksi exception dan mengekspor catatan yang dapat dilacak.

### Milestone C — layak dijual

- Invoice/deposit ledger, audit export, customer portal, signed webhook.
- Billing SKU/limits, device onboarding/decommission, installer app flow.
- Backup restore, monitoring, rollout/rollback, incident response.
- Tenant pentest, load and burst test, mobile release signing/store preparation.
- Kontrak layanan, privacy flow, SLA/RMA/support, prosedur migrasi vendor lama.

**Lulus:** tenant kedua tidak dapat mengakses data tenant pertama; onboarding/penagihan/support berfungsi; penawaran komersial didukung biaya dan kapasitas terukur.

### Milestone D — AI dan diferensiasi

- Python evaluators dan read-only Copilot dengan citation evidence.
- Energy audit dan readiness score; false-positive review.
- Dispatch proposal + approval, maintenance optimization dan bounded automation.
- C++/C custom hardware feasibility hanya bila volume, fitur dan supply-chain memberi alasan kuat.

## 3. Uji lapangan

| Kasus | Observasi dan bukti | Syarat lulus |
|---|---|---|
| Jalur kota/tol/basement | Fix/accuracy, coverage, timestamp, UI freshness | Gap dan ketidakpastian terlihat; recover tidak duplikat |
| Parkir semalam | Sleep current, aki, heartbeat | Batas electrical disetujui installer/OEM |
| Power loss | Backup behavior, posisi terakhir, alert | Alert sesuai kemampuan, tanpa klaim data ketika mati |
| Geofence edge | Ground-truth entry/exit, drift, dwell | False positives ditinjau; rule terversi |
| EV charging | Dashboard/OEM versus sample tracker | Akurasi per model terdokumentasi; unsupported tetap unknown |
| Refuel | Volume resmi/nota, level, kondisi tangki | Kalibrasi dan toleransi sensor tercatat |
| Offline 1–24 jam | Buffer capacity dan ordered recovery | Loss terukur, replay aman, latest state tidak mundur |
| Device replacement | Old/new install periods, credential revocation | History tetap benar; device lama tidak menulis setelah revoke |
| Driver replacement | Approval, task visibility, rating history | Akses berpindah sesuai assignment |
| Audio pilot | Indikator, volume, owner sesi, latency/network loss | Transparan dan terotorisasi; fallback komunikasi tersedia |

Uji potensi gangguan RF harus di lingkungan/metode yang sah, bukan menyalakan jammer di jalan umum. Uji kontrol kendaraan hanya oleh pihak berkompeten dalam prosedur yang disetujui; starter tidak memiliki kontrol tersebut.

## 4. Pengukuran produk

Baseline sebelum pilot: waktu mencari unit, menit triage insiden, false alert/hari, utilisasi, idle, biaya BBM/energi per km, biaya support/unit, unit tidak siap saat booking, dan waktu serah-terima. Gunakan periode serta komposisi armada yang sebanding; jangan mengklaim penghematan dari korelasi singkat.

## 5. Release gate

Daftar berikut menjadi pekerjaan wajib sebelum produksi, bukan prosedur persetujuan untuk membuat blueprint:

1. Pemilik domain menyetujui hasil pilot dan batas sensor per kendaraan.
2. Engineer menunjukkan test report, beban terukur, error budget dan restore drill.
3. Product/security menunjukkan akses, privacy dan incident handling yang dapat dipraktikkan.
4. Finance/operations menunjukkan harga, biaya, support dan garansi yang masuk akal.
5. Rilis bertahap: internal → tenant pilot → tenant terbatas → rollout lebih luas, dengan metrik dan rollback.
