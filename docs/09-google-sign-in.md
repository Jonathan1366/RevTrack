# Google Sign-In setup

The welcome, login, and registration views are implemented. Google identity uses
`google_sign_in` 7.2.0; web uses the official GIS-rendered button. No OAuth project
has been supplied yet, so the app explains that sign-in is not active and offers
an explicit demo. Google identity does not grant access to the demo API or create
a production RevTrack account. The current Go API remains a demo service.

Add these **public client IDs** to `.local/mobile.json` when available (retain
the existing entries). `scripts/dev.py` preserves these keys:

```json
{
  "GOOGLE_WEB_CLIENT_ID": "",
  "GOOGLE_SERVER_CLIENT_ID": "",
  "GOOGLE_IOS_CLIENT_ID": ""
}
```

For Android, create an Android OAuth client for package `id.revtrack.revtrack`
and the signing certificate SHA-1. Set `GOOGLE_SERVER_CLIENT_ID` to the OAuth
**Web application** client ID in the same Google Cloud project. Android does not
receive the iOS `clientId`.

For web, set `GOOGLE_WEB_CLIENT_ID` and register the development origin
`http://127.0.0.1:7357` (or the exact hostname and port used). The client ID is passed
to plugin initialization. GIS owns the sign-in button and reports authentication
through its event stream.

For iOS, set `GOOGLE_IOS_CLIENT_ID`. Add `CFBundleURLTypes` / `CFBundleURLSchemes`
to `ios/Runner/Info.plist` using that OAuth client's **REVERSED_CLIENT_ID**. This
must be the real value from Google; no placeholder scheme has been installed.
For macOS, the plugin additionally needs the documented keychain entitlement.

No client secret belongs in Flutter, a dart-define, or this repository.

After Google authentication, the app shows the returned identity and states that
fleet access is not yet available. Connecting production access requires server
verification of the ID token (signature, issuer, audience, expiry), account
provisioning, workspace membership checks, and a separate authenticated fleet
API. Do not treat client-side Google identity as fleet authorization.

Restart the application after adding native plugins or client IDs:

```sh
python3 scripts/dev.py --mobile emulator-5554
```

For visual review, **Coba demo** works without Google configuration. Live Google
sign-in and iOS callbacks still require verification once the project is supplied.

## Glass and media

The welcome bundles two real EV videos and three photographs/posters locally.
Videos are muted, user-pausable, stop in background and during demo navigation,
and do not autoplay with reduced motion. `assets/media/CREDITS.md` records sources.

Glass surfaces use bounded Flutter backdrop blur, translucent gradients, and
edge highlights. High-contrast mode uses opaque surfaces. Experimental refraction
via `liquid_glass_renderer` 0.2.0-dev.4 is implemented for controls and navigation,
but remains off by default: the Android GLES emulator duplicated portions of the
screen through the refractive layer. Set `"ENABLE_REFRACTIVE_GLASS": true` in
`.local/mobile.json` only to evaluate it on a supported native GPU. Web and
unsupported GPU backends always use blur. Physical-device frame timing and iOS
performance have not been validated.

Primary references:
- https://pub.dev/packages/google_sign_in
- https://pub.dev/packages/google_sign_in_android
- https://pub.dev/packages/google_sign_in_ios
- https://pub.dev/packages/google_sign_in_web
- https://pub.dev/packages/video_player
- https://pub.dev/packages/liquid_glass_renderer
