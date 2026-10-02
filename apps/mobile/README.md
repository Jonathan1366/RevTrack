# RevTrack Flutter

Aplikasi armada Android/iOS dengan Mapbox native. Warna biru elektrik, navy dan putih, font Inter yang dibundel lokal, navigasi ponsel, chart interaktif, workflow rental/servis, dan insight berbasis aturan.

Jalankan workspace lengkap dari root:

```bash
flutter devices
python3 scripts/dev.py --mobile <device-id>
```

Atau mode data contoh lokal:

```bash
flutter pub get
flutter run -d <device-id>
```

Konfigurasi build: `MAPBOX_ACCESS_TOKEN` public `pk.`, `MAPBOX_STYLE_URI`, `API_URL`, `DEMO_API_TOKEN`. Gunakan `--dart-define-from-file=../../.local/mobile.json`; konfigurasi tidak masuk Git. Tanpa token, peta skematik diberi label jelas. Mapbox attribution tetap terlihat. Data armada selalu simulasi pada workspace ini.

```bash
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Android dan iOS memerlukan toolchain platform. iOS deployment target 14+. Pengujian emulator diserahkan kepada pemilik sesuai permintaan; hasil build bukan verifikasi runtime. Preview web `python3 scripts/dev.py --web` tersedia untuk QA tambahan. Periksa [walkthrough](../../docs/08-demo-walkthrough.md) dan [verifikasi](../../docs/06-verification.md) untuk hasil aktual dan batas yang belum diuji.
