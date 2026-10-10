#!/bin/bash
# Assemble the release-compatible pkgroot from CI-built files. The runtime is
# source-built by CI; only the checksum-pinned firmware comes from NVIDIA.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPONENTS=${1:?usage: stage_release.sh COMPONENTS KEXTS RUNTIME OUT VERSION}
KEXTS=${2:?}
RUNTIME=${3:?}
OUT=${4:?}
VERSION=${5:?}
PKG="$OUT/pkgroot"

case "$VERSION" in *[!0-9A-Za-z._-]*|'') echo "STOP: invalid version" >&2; exit 2;; esac

need_file() { [ -f "$1" ] || { echo "STOP: missing required file: $1" >&2; exit 3; }; }
need_dir() { [ -d "$1" ] || { echo "STOP: missing required directory: $1" >&2; exit 3; }; }
no_links() {
  [ -z "$(find "$1" -type l -print -quit)" ] || { echo "STOP: runtime artifact may not contain symlinks" >&2; exit 3; }
}

need_dir "$COMPONENTS"
need_dir "$KEXTS/common/NVRM.kext"
need_dir "$KEXTS/common/NVRMFB.kext"
need_dir "$KEXTS/common/NVRMAGDC.kext"
need_dir "$KEXTS/NVAccel-15/NVAccel.kext"
need_dir "$KEXTS/NVAccel-26/NVAccel.kext"
need_file "$COMPONENTS/bin/NVMTLDriver"
need_file "$COMPONENTS/bin/libnvmtl_translate.dylib"
need_file "$COMPONENTS/bin/NullMothSafe.efi"
need_dir "$COMPONENTS/1401.app"
need_file "$COMPONENTS/1401.app/Contents/MacOS/1401"

# The runtime provenance and checksums are verified by the workflow first.
need_dir "$RUNTIME/Library/GPUBundles/NVMTLDriver.bundle"
need_dir "$RUNTIME/Library/GPUBundles/nvmtl"
need_file "$RUNTIME/Library/GPUBundles/nvmtl/libvulkan.dylib"
need_file "$RUNTIME/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib"
need_file "$RUNTIME/Library/GPUBundles/nvmtl/nvk_icd.json"
need_file "$RUNTIME/Library/GPUBundles/nvmtl-allow.txt"
need_dir "$RUNTIME/Users/Shared/nvfw/nvidia/610.57.04"
no_links "$RUNTIME"

rm -rf "$OUT"
mkdir -p "$PKG/Library/Extensions" "$PKG/Library/NullMoth/kexts/15" \
  "$PKG/Library/NullMoth/kexts/26" "$PKG/Library/GPUBundles" "$PKG/Users/Shared"

ditto "$KEXTS/common/NVRM.kext" "$PKG/Library/Extensions/NVRM.kext"
ditto "$KEXTS/common/NVRMFB.kext" "$PKG/Library/Extensions/NVRMFB.kext"
ditto "$KEXTS/common/NVRMAGDC.kext" "$PKG/Library/Extensions/NVRMAGDC.kext"
ditto "$KEXTS/NVAccel-15/NVAccel.kext" "$PKG/Library/NullMoth/kexts/15/NVAccel.kext"
ditto "$KEXTS/NVAccel-26/NVAccel.kext" "$PKG/Library/NullMoth/kexts/26/NVAccel.kext"

ditto "$RUNTIME/Library/GPUBundles/NVMTLDriver.bundle" "$PKG/Library/GPUBundles/NVMTLDriver.bundle"
ditto "$RUNTIME/Library/GPUBundles/nvmtl" "$PKG/Library/GPUBundles/nvmtl"
cp "$RUNTIME/Library/GPUBundles/nvmtl-allow.txt" "$PKG/Library/GPUBundles/nvmtl-allow.txt"
ditto "$RUNTIME/Users/Shared/nvfw" "$PKG/Users/Shared/nvfw"

# Insert repository-owned binaries built from this commit.
# Artifact uploads omit empty directories, including the runtime bundle's
# MacOS directory until its separately built executable is inserted here.
mkdir -p "$PKG/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS"
cp "$COMPONENTS/bin/NVMTLDriver" "$PKG/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver"
cp "$COMPONENTS/bin/libnvmtl_translate.dylib" "$PKG/Library/GPUBundles/nvmtl/libnvmtl_translate.dylib"
plutil -replace CFBundleShortVersionString -string "$VERSION" \
  "$PKG/Library/GPUBundles/NVMTLDriver.bundle/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" \
  "$PKG/Library/GPUBundles/NVMTLDriver.bundle/Contents/Info.plist"

cp "$ROOT/package/install.sh" "$ROOT/package/uninstall.sh" "$PKG/"
chmod 755 "$PKG/install.sh" "$PKG/uninstall.sh"

for p in "$PKG"/Library/Extensions/*.kext/Contents/Info.plist \
         "$PKG"/Library/NullMoth/kexts/*/NVAccel.kext/Contents/Info.plist \
         "$PKG"/Library/GPUBundles/NVMTLDriver.bundle/Contents/Info.plist; do
  plutil -lint "$p" >/dev/null
done

(
  cd "$PKG"
  find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done > SHA256SUMS
)

mkdir -p "$OUT/dist"
ARCHIVE="nullmoth-nvidia-$VERSION.tar.gz"
COPYFILE_DISABLE=1 tar -czf "$OUT/dist/$ARCHIVE" -C "$OUT" pkgroot
DRIVER_SHA=$(shasum -a 256 "$OUT/dist/$ARCHIVE" | cut -d ' ' -f 1)

# Reuse the app binary/resources built from this commit, but bind its package
# metadata to the tarball made immediately above. The DMG carries that exact
# tarball at /Volumes/1401/NullMoth/, which is one of the app's search paths.
APP="$OUT/1401.app"
ditto "$COMPONENTS/1401.app" "$APP"
cp "$COMPONENTS/bin/NullMothSafe.efi" "$APP/Contents/Resources/NullMothSafe.efi"
APP_PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PLIST"
plutil -replace NullMothDriverVersion -string "$VERSION" "$APP_PLIST"
plutil -replace NullMothDriverArchive -string "$ARCHIVE" "$APP_PLIST"
plutil -replace NullMothDriverSHA256 -string "$DRIVER_SHA" "$APP_PLIST"
plutil -replace NullMothDriverURL -string \
  "https://github.com/${GITHUB_REPOSITORY:-nullmoth/nvidia-macos-driver}/releases/download/v$VERSION/$ARCHIVE" \
  "$APP_PLIST"
rm -rf "$APP/Contents/_CodeSignature"
plutil -lint "$APP_PLIST" >/dev/null

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/dist/1401-Mac-$VERSION.zip"
DMGROOT="$OUT/dmgroot"
mkdir -p "$DMGROOT/NullMoth"
ditto "$APP" "$DMGROOT/1401.app"
cp "$OUT/dist/$ARCHIVE" "$DMGROOT/NullMoth/$ARCHIVE"
hdiutil create -quiet -ov -format UDZO -volname 1401 \
  -srcfolder "$DMGROOT" "$OUT/dist/1401-Mac-$VERSION.dmg"

printf 'version=%s\nsource_commit=%s\nsigned=no\nruntime_source_built=yes\nnvidia_shared_bundle=included-no\n' \
  "$VERSION" "${SOURCE_SHA:-${GITHUB_SHA:-unknown}}" > "$OUT/dist/BUILD-MANIFEST.txt"
(
  cd "$OUT/dist"
  find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done > SHA256SUMS
)
