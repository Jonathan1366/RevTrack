# Android release + Mapbox

RevTrack's native Android map is enabled at compile time with `MAPBOX_ACCESS_TOKEN` and `MAPBOX_STYLE_URI` supplied through Flutter `--dart-define-from-file`. The token used in an Android app must be a **public Mapbox token** beginning with `pk.`. Do not put Mapbox secret tokens or RevTrack server secrets in Git.

## 1. Pull the repository changes

```sh
git pull --rebase origin main
```

## 2. Create the local Android build config

From the repository root:

```sh
mkdir -p .local
cp apps/mobile/config/mobile.android.example.json .local/mobile.android.json
```

Edit `.local/mobile.android.json` and replace the Mapbox placeholder:

```json
{
  "API_URL": "",
  "DEMO_API_TOKEN": "",
  "MAPBOX_ACCESS_TOKEN": "pk.your-public-mapbox-token",
  "MAPBOX_STYLE_URI": "mapbox://styles/mapbox/standard"
}
```

`.local/` is ignored by Git. When `API_URL` is empty, fleet records remain the built-in demo dataset but the native Mapbox map, Mapbox Geocoding and Directions requests can use the internet. This is useful to validate the Android UI before the backend is deployed.

For a standalone full-stack staging build, use an HTTPS backend instead:

```json
{
  "API_URL": "https://api-staging.revtrack.example",
  "DEMO_API_TOKEN": "replace-with-the-staging-user-token",
  "MAPBOX_ACCESS_TOKEN": "pk.your-public-mapbox-token",
  "MAPBOX_STYLE_URI": "mapbox://styles/mapbox/standard"
}
```

Do not ship the current demo bearer-token design as production authentication. Replace it with real user authentication before commercial release.

## 3. Build an installable APK

```sh
bash scripts/build_android.sh apk
```

The script validates that a real-looking public Mapbox token is present before Flutter starts the release build. Output:

```text
apps/mobile/build/app/outputs/flutter-apk/app-release.apk
```

Install on a connected Android phone:

```sh
adb install -r apps/mobile/build/app/outputs/flutter-apk/app-release.apk
```

The phone needs normal internet access for Mapbox. It does not need to be connected to the Mac for Mapbox itself.

## 4. Build the Play Store bundle

```sh
bash scripts/build_android.sh aab
```

Output:

```text
apps/mobile/build/app/outputs/bundle/release/app-release.aab
```

The current Android project still uses the debug signing key for release convenience. Configure a production upload/signing key before Play Store distribution.

## 5. Backend behavior

The API container lives at `services/api/Dockerfile`. In cloud/container environments it listens using:

```text
HOST=0.0.0.0
PORT=8080
```

and still requires different `REVTRACK_DEMO_TOKEN` and `REVTRACK_DEVICE_TOKEN` values of at least 24 characters. A cloud platform must terminate HTTPS (or put the container behind an HTTPS reverse proxy/load balancer) before an Android standalone build points `API_URL` at it.

Local development remains loopback-only by default. Android USB development can continue using `adb reverse tcp:8080 tcp:8080`.

## What works in this milestone

- native Mapbox Standard map on Android
- online Mapbox tiles/styles
- Jakarta address/region search through Mapbox Geocoding
- Mapbox Directions route preview
- optional traffic overlay where Mapbox data/layers are available
- vehicle markers sourced from RevTrack demo/API data
- release APK/AAB build that fails early when the Mapbox token is missing
- Go backend container ready to be deployed by a cloud platform

This milestone does not yet add a physical vehicle tracker, production identity/authentication, production database, vehicle commands, or a hosted RevTrack cloud instance.
