# Releasing AQI Bar

Keep the bundle identifier `local.frizurd.aqibar` and Developer ID team stable across releases. Update `CFBundleShortVersionString` and `CFBundleVersion` in `build.sh` before building.

Use a Developer ID Application certificate with its private key in Keychain. Store notarization credentials with `xcrun notarytool store-credentials`, then set `NOTARY_PROFILE` to that Keychain profile's name. Credentials stay outside the repository.

From the repository root:

```sh
xcrun swift test --disable-sandbox
./build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' 'build/AQI Bar.app/Contents/Info.plist')
archive="build/AQI-Bar-${version}-macOS-arm64.zip"
ditto -c -k --keepParent 'build/AQI Bar.app' "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple 'build/AQI Bar.app'
xcrun stapler validate 'build/AQI Bar.app'
codesign --verify --deep --strict 'build/AQI Bar.app'
spctl --assess --type execute --verbose=2 'build/AQI Bar.app'
ditto -c -k --keepParent 'build/AQI Bar.app' "$archive"
(cd build && shasum -a 256 "$(basename "$archive")" > SHA256SUMS.txt)
```

Continue only if notarization is accepted and every verification succeeds. Recreate the ZIP after stapling so the download contains the notarization ticket. The current release build targets Apple silicon; do not use the `arm64` filename for an Intel build.

Commit and push the source to `main`, then publish a matching `v<version>` tag and GitHub release with the final ZIP and checksum file. Avoid replacing existing release assets: a new version keeps Homebrew checksums stable.

In `frizurd/homebrew-tap`, update `Casks/aqi-bar.rb` with the version and final archive's SHA-256. Run `brew style --cask frizurd/tap/aqi-bar`, `brew audit --cask --strict frizurd/tap/aqi-bar`, and `brew fetch --cask frizurd/tap/aqi-bar` before publishing the tap update. Test installation with the downloaded archive and verify its signature and notarization ticket.
