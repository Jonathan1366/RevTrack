#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE="$ROOT/apps/mobile"
CONFIG="${REVTRACK_MOBILE_CONFIG:-$ROOT/.local/mobile.android.json}"
FORMAT="${1:-apk}"

case "$FORMAT" in
  apk|aab) ;;
  *)
    echo "Usage: bash scripts/build_android.sh [apk|aab]" >&2
    exit 2
    ;;
esac

if [[ ! -f "$CONFIG" ]]; then
  cat >&2 <<EOF
Missing RevTrack Android config: $CONFIG

Create it from the template:
  mkdir -p "$ROOT/.local"
  cp "$MOBILE/config/mobile.android.example.json" "$CONFIG"

Then set MAPBOX_ACCESS_TOKEN to your public pk. token.
For a standalone full-stack build, set API_URL to an HTTPS RevTrack backend.
EOF
  exit 2
fi

cd "$MOBILE"
dart run tool/validate_mobile_config.dart "$CONFIG"
flutter pub get

if [[ "$FORMAT" == "apk" ]]; then
  flutter build apk --release --dart-define-from-file="$CONFIG"
  echo
  echo "RevTrack APK ready:"
  echo "$MOBILE/build/app/outputs/flutter-apk/app-release.apk"
else
  flutter build appbundle --release --dart-define-from-file="$CONFIG"
  echo
  echo "RevTrack Android App Bundle ready:"
  echo "$MOBILE/build/app/outputs/bundle/release/app-release.aab"
fi
