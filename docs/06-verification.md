# Catatan verifikasi RevTrack

Catatan ini membedakan pemeriksaan software lokal dengan validasi produksi dan kendaraan fisik. Data workspace adalah simulasi. Diperbarui 2 Oktober 2026.

## Hasil pemeriksaan

| Pemeriksaan | Hasil saat ini |
|---|---|
| Go API: `go test -race ./...` | Lulus pada pemeriksaan ulang: 20 fungsi test, mencakup isolasi tenant, replay, persistence, rental/maintenance, report dan CSV |
| Go API: `go vet ./...` | Lulus pada pemeriksaan ulang |
| Smoke HTTP API | Flow fleet, telemetry, assignment, alert, rental→return, work order→complete serta persistence restart telah diperiksa |
| Launcher Python | Validasi syntax/help, pemilihan target, penolakan desktop dan guard port; mode native belum dijalankan |
| Flutter `analyze` dan tests | Analyze: tidak ada isu. Sebelas tests lulus: tujuh widget tests termasuk layout ponsel 390×844/peta/Operasi, empat tests data/API |
| Android APK build | Lulus `flutter build apk --debug --dart-define-from-file=../../.local/mobile.json`; APK lokal di `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk` |
| Android emulator/perangkat runtime | Tidak dijalankan, mengikuti permintaan pengguna untuk melakukan pengujian manual sendiri |
| iOS build | Belum dijalankan: Xcode tidak lengkap dan CocoaPods belum tersedia pada mesin pengembangan |
| Mapbox browser | Style, tiles dan marker asli sudah diamati pada QA; bukan verifikasi SDK Android/iOS |
| PostgreSQL/PostGIS migration | Belum dijalankan; service demo memakai snapshot JSON, bukan SQL |
| GitHub Actions | Workflow Go/Flutter disediakan dengan referensi action SHA; hasil CI remote belum diklaim |

## Yang diuji dan maknanya

Backend menjaga pemisahan kredensial pengguna/perangkat, binding tenant/device server-side, batas payload, validasi telemetry, ring history terbatas, penolakan replay/out-of-order, unknown sensor, konflik assignment, interval booking, return, service, audit dan ekspor tenant. Race tests memeriksa akses concurrent yang dicakup pengujian; bukan benchmark kapasitas 10.000 unit.

Snapshot lokal memakai file private dan atomic rename untuk satu proses. Pengujian restart/rollback tidak membuktikan failover, enkripsi-at-rest aplikasi atau recovery power loss produksi. Reports menyimpulkan sampel tersimpan, tidak mengklaim trip lengkap, kWh/consumption atau pembuktian fraud.

Android dipin ke AGP 8.13.2, Gradle 8.14.4, Kotlin 2.3.20, compile/target SDK 36. Kombinasi AGP 9 bawaan Flutter 3.44 gagal karena migrasi built-in Kotlin belum seragam antar-plugin native. Build AGP 8 lulus dengan peringatan migrasi untuk versi Flutter mendatang. Ikuti [panduan Flutter](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin) dan [catatan AGP](https://developer.android.com/build/releases/agp-8-13-0-release-notes) ketika memperbarui toolchain; jangan menaikkan dependency tanpa build ulang. Build debug memakai signing development, bukan paket rilis toko.

## Belum tervalidasi

- GNSS dan CAN/SOC/fuel dari kendaraan nyata, setiap model/tahun/varian.
- Power cut, tow, jamming, reconnect storm, buffer hardware, OTA dan installer commissioning.
- Kontrol kendaraan/interkom: tidak ada endpoint atau koneksi aktuator/audio pada demo.
- Auth produksi, signing release, multi-tenant SaaS, load test, backup/restore cloud dan billing.
- AI generatif/agent execution: UI memakai analisis deterministik, tanpa model eksternal.
- Navigasi suara/offline Mapbox, katalog POI Indonesia lengkap, dan seluruh fitur Google Maps.
- Full workflow kontrak, deposit, inspeksi, invoice, settlement dan aplikasi driver/penumpang marketplace.

## Perintah untuk mengulang pemeriksaan

```bash
cd services/api
go test -race ./...
go vet ./...
cd ../../apps/mobile
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=../../.local/mobile.json
cd ../..
python3 scripts/dev.py --help
python3 scripts/dev.py --mobile <device-id>
```

Pemeriksaan fisik dan gerbang peluncuran dijelaskan di [pilot dan backlog](05-pilot-delivery.md) dan [IoT/security](02-iot-security.md). Tidak ada klaim kesiapan komersial sebelum gerbang tersebut lulus.
