#!/bin/bash
# Build the four unsigned x86_64 kext bundles without loading them.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OGKM=${OGKM:?set OGKM to NVIDIA open-gpu-kernel-modules 610.57.04}
OUT=${1:?usage: build_kexts_ci.sh OUT_DIR}
JOBS=${JOBS:-3}

version=$(awk '/^NVIDIA_VERSION[[:space:]]*=/{print $3; exit}' "$OGKM/version.mk")
[ "$version" = 610.57.04 ] || { echo "STOP: OGKM 610.57.04 required, found ${version:-unknown}" >&2; exit 2; }

SDK=$(xcrun --sdk macosx --show-sdk-path)
KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
CLANG=$(xcrun -f clang)
CLANGXX=$(xcrun -f clang++)
NV="$OGKM/src/nvidia"
KMS="$OGKM/src/nvidia-modeset"
OBJ="$OUT/objects"
mkdir -p "$OBJ" "$OUT/common" "$OUT/NVAccel-15" "$OUT/NVAccel-26"

kernel_flags=(
  -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR"
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
  -DNV_MACOSX -DNV_DARWIN
  -fno-builtin -fno-common -fno-stack-protector -mno-red-zone
  -Wno-unused-parameter -Wno-unused-function -Wno-deprecated-declarations -O2
)

rm_includes=(
  -I"$NV/arch/nvalloc/unix/include" -I"$NV/arch/nvalloc/common/inc"
  -I"$NV/arch/nvalloc/common/inc/gsp" -I"$NV/arch/nvalloc/common/inc/deprecated"
  -I"$OGKM/src/common/sdk/nvidia/inc" -I"$OGKM/src/common/sdk/nvidia/inc/hw"
  -I"$OGKM/src/common/inc" -I"$OGKM/src/common/shared/inc"
  -I"$NV/inc" -I"$NV/inc/os" -I"$NV/inc/kernel" -I"$NV/kernel/inc"
  -I"$NV/interface" -I"$NV/generated" -I"$NV/src/mm/uvm/interface"
  -I"$NV/inc/libraries" -I"$NV/src/libraries"
  -I"$OGKM/src/common/nvlink/interface" -I"$OGKM/src/common/nvlink/inband/interface"
  -I"$OGKM/src/common/inc/swref" -I"$OGKM/src/common/inc/swref/published"
  -I"$OGKM/src/common/uproc/os/libos-v2.0.0/include"
  -I"$OGKM/src/common/uproc/os/common/include" -I"$OGKM/src/common/inc/displayport"
)
kms_includes=(
  -I"$KMS/os-interface/include" -I"$KMS/kapi/interface" -I"$KMS/kapi/include"
  -I"$KMS/interface" -I"$KMS/include" -I"$KMS/generated"
  -I"$OGKM/src/common/unix/nvidia-push/interface"
  -I"$OGKM/src/common/unix/nvidia-push/include"
  -I"$OGKM/src/common/unix/nvidia-3d/interface"
  -I"$OGKM/src/common/unix/nvidia-3d/include"
  -I"$OGKM/src/common/unix/common/inc"
  -I"$OGKM/src/common/unix/common/utils/interface"
  -I"$OGKM/src/common/modeset" -I"$OGKM/src/common/displayport/inc"
  -I"$OGKM/src/common/displayport/inc/dptestutil"
  -I"$OGKM/src/common/unix/xzminidec/interface"
  -I"$OGKM/src/common/unix/nvidia-headsurface"
)

join_flags() { printf '%q ' "$@"; }
extra_flags=$(join_flags "${kernel_flags[@]}")

# NVIDIA's Makefiles know the complete, generated source lists.  The appended
# makefile stops before their ELF-only link and archives the Mach-O objects.
make -C "$NV" -f Makefile -f "$ROOT/build/ogkm-darwin.mk" darwin-archive -j"$JOBS" \
  TARGET_OS=Darwin TARGET_ARCH=x86_64 CC="$CLANG" CXX="$CLANGXX" \
  NV_BUILD_USER=github NV_BUILD_HOST=actions NV_AUTO_DEPEND=0 \
  EXTRA_CFLAGS="$extra_flags" DARWIN_ARCHIVE="$OBJ/libnvkernel.a"
make -C "$KMS" -f Makefile -f "$ROOT/build/ogkm-darwin.mk" darwin-archive -j"$JOBS" \
  TARGET_OS=Darwin TARGET_ARCH=x86_64 CC="$CLANG" CXX="$CLANGXX" \
  NV_BUILD_USER=github NV_BUILD_HOST=actions NV_AUTO_DEPEND=0 \
  EXTRA_CFLAGS="$extra_flags" DARWIN_ARCHIVE="$OBJ/libnvmodeset.a"

compile_cxx() {
  local src=$1 out=$2; shift 2
  "$CLANGXX" "${kernel_flags[@]}" "${rm_includes[@]}" "${kms_includes[@]}" \
    -I"$ROOT/kexts/NVRM" -std=c++17 -fno-rtti -fno-exceptions "$@" -c "$src" -o "$out"
}
compile_c() {
  local src=$1 out=$2; shift 2
  "$CLANG" "${kernel_flags[@]}" "${rm_includes[@]}" "${kms_includes[@]}" \
    -I"$ROOT/kexts/NVRM" -std=gnu11 -D_LANGUAGE_C -DNVRM "$@" -c "$src" -o "$out"
}
link_kext() {
  local exe=$1; shift
  "$CLANGXX" -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext \
    -lkmodc++ -lkmod -lcc_kext "$@" -o "$exe"
}
bundle() {
  local name=$1 plist=$2 exe=$3 dest=$4
  mkdir -p "$dest/$name.kext/Contents/MacOS"
  cp "$plist" "$dest/$name.kext/Contents/Info.plist"
  cp "$exe" "$dest/$name.kext/Contents/MacOS/$name"
}

nvrm_objects=()
for src in NVRM.cpp os-xnu.cpp os-xnu2.cpp os-nvkms-xnu.cpp nv_xnu_stubs.cpp \
           nvrm_gpuva.cpp nvrm_surfshare.cpp nvrm_fbinfo.cpp nvkms_shaders.cpp; do
  obj="$OBJ/${src%.*}.o"; compile_cxx "$ROOT/kexts/NVRM/$src" "$obj"; nvrm_objects+=("$obj")
done
for src in nvrm_pageoff.c nvrm_kapi_fields.c; do
  obj="$OBJ/${src%.*}.o"; compile_c "$ROOT/kexts/NVRM/$src" "$obj"; nvrm_objects+=("$obj")
done
link_kext "$OBJ/NVRM" "${nvrm_objects[@]}" \
  -Wl,-force_load,"$OBJ/libnvkernel.a" -Wl,-force_load,"$OBJ/libnvmodeset.a"
bundle NVRM "$ROOT/kexts/NVRM/Info.plist" "$OBJ/NVRM" "$OUT/common"

compile_cxx "$ROOT/kexts/NVRMFB/fb/nvrm-fb.cpp" "$OBJ/NVRMFB.o" \
  -I"$ROOT/kexts/NVRMFB" -I"$ROOT/kexts/NVRMFB/fb"
link_kext "$OBJ/NVRMFB" "$OBJ/NVRMFB.o"
bundle NVRMFB "$ROOT/kexts/NVRMFB/fb/Info.plist" "$OBJ/NVRMFB" "$OUT/common"

compile_cxx "$ROOT/kexts/NVRMAGDC/nvrm-agdc.cpp" "$OBJ/NVRMAGDC.o" -I"$ROOT/kexts/NVRMAGDC"
link_kext "$OBJ/NVRMAGDC" "$OBJ/NVRMAGDC.o"
bundle NVRMAGDC "$ROOT/kexts/NVRMAGDC/Info.plist" "$OBJ/NVRMAGDC" "$OUT/common"

for major in 15 26; do
  tahoe=(); [ "$major" = 26 ] && tahoe=(-DNM_TAHOE)
  compile_cxx "$ROOT/kexts/NVRM/accel/nvrm-accel.cpp" "$OBJ/NVAccel-$major.o" \
    -I"$ROOT/kexts/NVRM/accel" -I"$ROOT/kexts/NVRM/accel/iofam" \
    -I"$ROOT/kexts/NVRM/accel/re" "${tahoe[@]}"
  link_kext "$OBJ/NVAccel-$major" "$OBJ/NVAccel-$major.o"
  bundle NVAccel "$ROOT/kexts/NVRM/accel/Info.plist" "$OBJ/NVAccel-$major" "$OUT/NVAccel-$major"
done

printf 'source_commit=%s\nogkm=%s\narchitecture=x86_64\nsigned=no\n' \
  "${GITHUB_SHA:-unknown}" "$version" > "$OUT/BUILD-MANIFEST.txt"
