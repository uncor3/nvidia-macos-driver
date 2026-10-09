#!/bin/sh
set -eu

# CI-only source runtime builder. All source trees must already be checked
# out at the commits recorded by the workflow; this script does no networking.

if [ "$#" -ne 2 ]; then
    echo "usage: $0 DEPS_DIR OUTPUT_DIR" >&2
    exit 2
fi

DEPS=$1
OUT=$2
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MESA="$DEPS/mesa"
OGKM="$DEPS/open-gpu-kernel-modules"
VK_HEADERS="$DEPS/Vulkan-Headers"
VK_LOADER="$DEPS/Vulkan-Loader"
TOOLS="$DEPS/tools"

for d in "$MESA" "$OGKM" "$VK_HEADERS" "$VK_LOADER"; do
    test -d "$d" || { echo "missing source tree: $d" >&2; exit 1; }
done

mkdir -p "$TOOLS/bin" "$OUT/Library/GPUBundles/nvmtl"
mkdir -p "$OUT/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS"

# The patch imports the macOS NVRM backend and expects this exact nested tree.
mkdir -p "$MESA/src/nouveau/vulkan/nvkmd/nvrm"
ln -s "$OGKM" "$MESA/src/nouveau/vulkan/nvkmd/nvrm/open-gpu-kernel-modules"
patch -d "$MESA" -p1 -F 0 -N < "$ROOT/nvk/nvk-macos.patch"

# Build mesa_clc and vtn_bindgen2 from the same pinned Mesa source. The final
# NVK library then consumes these host tools with LLVM disabled in the runtime.
meson setup "$DEPS/mesa-clc-build" "$MESA" \
    --buildtype=release \
    -Dplatforms= \
    -Dgallium-drivers= \
    -Dvulkan-drivers= \
    -Degl=disabled \
    -Dglx=disabled \
    -Dllvm=enabled \
    -Dmesa-clc=enabled \
    -Dbuild-tests=false
meson compile -C "$DEPS/mesa-clc-build" mesa_clc vtn_bindgen2
MESA_CLC=$(find "$DEPS/mesa-clc-build" -type f -name mesa_clc -print -quit)
VTN_BINDGEN=$(find "$DEPS/mesa-clc-build" -type f -name vtn_bindgen2 -print -quit)
test -n "$MESA_CLC"
test -n "$VTN_BINDGEN"
cp "$MESA_CLC" "$TOOLS/bin/mesa_clc"
cp "$VTN_BINDGEN" "$TOOLS/bin/vtn_bindgen2"
test -x "$TOOLS/bin/mesa_clc"
test -x "$TOOLS/bin/vtn_bindgen2"
PATH="$TOOLS/bin:$PATH"
export PATH

meson setup "$DEPS/nvk-build" "$MESA" \
    --buildtype=debugoptimized \
    -Dplatforms= \
    -Dgallium-drivers= \
    -Dvulkan-drivers=nouveau \
    -Degl=disabled \
    -Dglx=disabled \
    -Dglvnd=disabled \
    -Dllvm=disabled \
    -Dmesa-clc=system \
    -Dshared-glapi=disabled \
    -Dvulkan-layers= \
    -Dtools= \
    -Dbuild-tests=false \
    -Dexpat=disabled \
    -Dzstd=disabled \
    -Dlibunwind=disabled \
    -Dlmsensors=disabled \
    -Dvalgrind=disabled \
    -Dxlib-lease=disabled \
    -Dgallium-rusticl=false \
    -Dspirv-tools=disabled \
    "-Dc_args=-ffile-prefix-map=$MESA=/src -ffile-prefix-map=$DEPS=/build" \
    "-Dcpp_args=-ffile-prefix-map=$MESA=/src -ffile-prefix-map=$DEPS=/build" \
    "-Drust_args=--remap-path-prefix=$MESA=/src --remap-path-prefix=$DEPS=/build"
meson compile -C "$DEPS/nvk-build" src/nouveau/vulkan/libvulkan_nouveau.dylib
cp "$DEPS/nvk-build/src/nouveau/vulkan/libvulkan_nouveau.dylib" \
    "$OUT/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib"
UNRESOLVED=$(nm -m "$OUT/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib" \
    | grep '(undefined)' | grep -v weak | grep 'dynamically looked up' || true)
test -z "$UNRESOLVED" || {
    echo "unresolved strong references in libvulkan_nouveau.dylib:" >&2
    echo "$UNRESOLVED" >&2
    exit 1
}
strip -S "$OUT/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib"

cmake -S "$VK_HEADERS" -B "$DEPS/vulkan-headers-build" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DEPS/vulkan-headers-install" \
    -DVULKAN_HEADERS_ENABLE_TESTS=OFF
cmake --install "$DEPS/vulkan-headers-build"

cmake -S "$VK_LOADER" -B "$DEPS/vulkan-loader-build" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_INSTALL_PREFIX="$DEPS/vulkan-loader-install" \
    -DVULKAN_HEADERS_INSTALL_DIR="$DEPS/vulkan-headers-install" \
    -DBUILD_TESTS=OFF \
    -DBUILD_WSI_XCB_SUPPORT=OFF \
    -DBUILD_WSI_XLIB_SUPPORT=OFF \
    -DBUILD_WSI_WAYLAND_SUPPORT=OFF
cmake --build "$DEPS/vulkan-loader-build" --target install
LOADER=$(find "$DEPS/vulkan-loader-install" -type f -name 'libvulkan*.dylib' | head -n 1)
test -n "$LOADER"
cp "$LOADER" "$OUT/Library/GPUBundles/nvmtl/libvulkan.dylib"

cp "$ROOT/package/runtime/NVMTLDriver-Info.plist" \
    "$OUT/Library/GPUBundles/NVMTLDriver.bundle/Contents/Info.plist"
cp "$ROOT/package/runtime/nvk_icd.json" "$OUT/Library/GPUBundles/nvmtl/nvk_icd.json"
cp "$ROOT/package/runtime/nvmtl-allow.txt" "$OUT/Library/GPUBundles/nvmtl-allow.txt"
chmod 755 "$OUT/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib" \
    "$OUT/Library/GPUBundles/nvmtl/libvulkan.dylib"

file "$OUT/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib" | grep -q 'x86_64'
file "$OUT/Library/GPUBundles/nvmtl/libvulkan.dylib" | grep -q 'x86_64'
plutil -lint "$OUT/Library/GPUBundles/NVMTLDriver.bundle/Contents/Info.plist"

# Do not accidentally ship Homebrew paths in runtime load commands.
if otool -L "$OUT/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib" \
    "$OUT/Library/GPUBundles/nvmtl/libvulkan.dylib" | grep -E '/(usr/local|opt/homebrew)/'; then
    echo "runtime library contains a Homebrew dependency" >&2
    exit 1
fi
