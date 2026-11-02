#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

# Prefer the installed distribution certificate; never silently fall back to ad hoc.
signing_identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  identities=("${(@f)$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-F]+) "Developer ID Application:.*"$/\1/p')}")
  if (( ${#identities} != 1 )) || [[ -z "${identities[1]}" ]]; then
    print -u2 'Set CODE_SIGN_IDENTITY to a signing certificate name or SHA-1 hash.'
    print -u2 'Expected one valid Developer ID Application identity. Run: security find-identity -v -p codesigning'
    print -u2 'For an explicitly ad-hoc local build only, set CODE_SIGN_IDENTITY=-.'
    exit 1
  fi
  signing_identity="${identities[1]}"
fi

/usr/bin/xcrun swift build --disable-sandbox -c release
app="$PWD/build/AQI Bar.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp .build/release/AQIBar "$app/Contents/MacOS/AQIBar"
iconset="$PWD/build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  /usr/bin/sips -z "$double" "$double" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AQIBar</string>
<key>CFBundleIdentifier</key><string>local.frizurd.aqibar</string>
<key>CFBundleName</key><string>AQI Bar</string>
<key>CFBundleDisplayName</key><string>AQI Bar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "$signing_identity" == - ]]; then
  /usr/bin/codesign --force --sign - "$app"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$signing_identity" "$app"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
signature=$(/usr/bin/codesign --display --verbose=2 "$app" 2>&1)
if [[ "$signing_identity" != - ]]; then
  team_id=$(print -r -- "$signature" | /usr/bin/sed -n 's/^TeamIdentifier=//p')
  if [[ -z "$team_id" || "$team_id" == 'not set' || "$signature" == *'Signature=adhoc'* ]]; then
    print -u2 'Signing failed: expected a certificate signature with a team ID.'
    exit 1
  fi
fi
print -r -- "$signature"
print "Built $app"
