# Development

The Swift package has two targets. `AQICore` owns AQI categories, IQAir requests, the saved location, and cached readings. `AQIBar` contains the AppKit menu bar item, SwiftUI settings, Apple Maps search, and Keychain access.

Call `store.select(.fixed(location))` to change city, or `store.refresh()` to fetch again. The store cancels the previous request and ignores late responses, so an old city cannot overwrite a new selection. Its provider protocol accepts a fake transport for tests.

## Menu bar rendering

`StatusRenderer` draws the label with `NSFont.menuBarFont(ofSize: 0)`. A non-template image preserves its colors when AppKit would otherwise recolor the status button. The button has an accessibility label, tooltip, and native menu. Above 150, the native font also becomes bold.

| Category | RGB |
| --- | --- |
| Good | `#a6da95` |
| Moderate | `#eed49f` |
| Unhealthy for sensitive groups | `#f5a97f` |
| Unhealthy | `#ed8796` |
| Very unhealthy | `#c6a0f6` |
| Hazardous | `#ff6685` |

## Build and test

```sh
./build.sh
xcrun swift test --disable-sandbox
```

The build creates `build/AQI Bar.app` for the current Mac's architecture. By default it selects the sole valid Developer ID Application identity from Keychain, signs with a secure timestamp and hardened runtime, and verifies the signature and team ID. If there are multiple identities, set `CODE_SIGN_IDENTITY` to the intended certificate name or SHA-1 hash. Missing or ambiguous identities fail the build instead of silently producing an ad-hoc signature. `CODE_SIGN_IDENTITY=- ./build.sh` explicitly opts into an ad-hoc local build. Signing does not notarize the app.

`--disable-sandbox` avoids nesting SwiftPM's build sandbox inside an agent's sandbox. It does not change the app's permissions.

Tests use separate UserDefaults suites. They cover AQI boundaries, malformed responses, quota errors, stale readings, city changes, cache recovery, retries, cancellation, and API-key redaction.

See [releasing](releasing.md) for notarization, packaging, and Homebrew updates.

## Rebuild screenshots

From the repository root:

```sh
"build/AQI Bar.app/Contents/MacOS/AQIBar" --render-preview "$PWD/docs/images"
```

This renders the actual settings views with sample data and draws the menu bar labels through `StatusRenderer`. It creates light and dark settings images, a color strip, the location search, a reading, and the combined demo. The demo's title bars and layout are presentation framing. It makes no API requests, captures no desktop content, and leaves the real app's preferences alone.

To check the live services with your configured key:

```sh
"build/AQI Bar.app/Contents/MacOS/AQIBar" --check
"build/AQI Bar.app/Contents/MacOS/AQIBar" --check-location "Jakarta, Indonesia"
```

## Credentials

An explicit key is stored as a generic password in Keychain. For migration from the original plugin, first launch looks for `~/.config/sketchybar/secrets/iqair.key` and copies the key into Keychain. If that import fails, the app falls back to reading the existing file. Neither the source nor the app bundle contains an API key.

The IQAir endpoint is documented in the [IQAir API reference](https://api-docs.iqair.com/). Apple documents the font in [`menuBarFont(ofSize:)`](https://developer.apple.com/documentation/appkit/nsfont/menubarfont(ofsize:)).
