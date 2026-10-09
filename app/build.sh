#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
OUT=${1:-build}; APP=$OUT/1401.app
APP_VERSION=${APP_VERSION:-1.0.14}
APP_BUILD=${APP_BUILD:-15}
DRIVER_VERSION=${DRIVER_VERSION:-1.0.9}
DRIVER_ARCHIVE=${DRIVER_ARCHIVE:-nullmoth-nvidia-$DRIVER_VERSION.tar.gz}
DRIVER_URL=${DRIVER_URL:-https://github.com/nullmoth/nvidia-macos-driver/releases/download/v1.0.13/$DRIVER_ARCHIVE}
DRIVER_SHA256=${DRIVER_SHA256:-9dbfdb1b1359e2ef4166a46905ee195774b0b4ba20be083a8111ef550b1e5789}
case "$APP_VERSION:$APP_BUILD:$DRIVER_VERSION:$DRIVER_SHA256" in
  *[!0-9A-Za-z._:-]*) echo "STOP: invalid app/package metadata" >&2; exit 2;;
esac
[ "${#DRIVER_SHA256}" -eq 64 ] || { echo "STOP: DRIVER_SHA256 must be 64 lowercase hexadecimal characters" >&2; exit 2; }
case "$DRIVER_SHA256" in *[!0-9a-f]*) echo "STOP: DRIVER_SHA256 must be lowercase hexadecimal" >&2; exit 2;; esac
[ -f Resources/NullMothSafe.efi ] || { echo "STOP: Resources/NullMothSafe.efi missing (build efi-safe first)"; exit 1; }
SDK=$(xcrun --sdk macosx --show-sdk-path)
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -target x86_64-apple-macos15.0 -sdk "$SDK" -framework WebKit -framework Metal -framework IOKit \
  Sources/main.swift Sources/profile.swift -o "$APP/Contents/MacOS/1401"
cp Resources/* "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/nullmoth-setup.sh"
IS=$(mktemp -d)/m.iconset; mkdir -p "$IS"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/moth-mark.jpg --setProperty format png --out "$IS/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/moth-mark.jpg --setProperty format png --out "$IS/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$IS" -o "$APP/Contents/Resources/1401.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>1401</string>
<key>CFBundleIconFile</key><string>1401</string>
<key>CFBundleIdentifier</key><string>com.nullmoth.1401</string>
<key>CFBundleName</key><string>1401</string>
<key>CFBundleDisplayName</key><string>1401</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD</string>
<key>NullMothDriverVersion</key><string>$DRIVER_VERSION</string>
<key>NullMothDriverArchive</key><string>$DRIVER_ARCHIVE</string>
<key>NullMothDriverURL</key><string>$DRIVER_URL</string>
<key>NullMothDriverSHA256</key><string>$DRIVER_SHA256</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHumanReadableCopyright</key><string>© 2026 NullMoth Systems</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>1401 asks macOS for your password to install the driver, and to restart when you click Restart.</string>
</dict></plist>
PL
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
else
  echo "leaving $APP unsigned (set SIGN_IDENTITY to sign it)"
fi
echo "built $APP ($(du -sh "$APP" | cut -f1))"
