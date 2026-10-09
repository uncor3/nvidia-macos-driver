# Building unsigned artifacts

The GitHub workflows build the installable payload in three independent jobs and then package only artifacts produced from the same source commit. Nothing produced here is signed or notarized.

## 1. Project components

Run **Build unsigned** (`.github/workflows/build.yml`). It builds the repository-owned Metal driver, AIR-to-SPIR-V translator, EFI helper, and installer application. Its artifact is named `nullmoth-unsigned-<commit>`. A manual run also invokes the source-runtime workflow, so both artifacts normally share one run ID.

## 2. Kernel extensions

Run **Build kexts** (`.github/workflows/build-kexts.yml`). It builds the kexts against the pinned NVIDIA open-gpu-kernel-modules source. Its artifact is named `nullmoth-kexts-<commit>`.

## 3. User-space runtime and firmware

Run **Build source runtime** (`.github/workflows/build-runtime.yml`), either through the manual `build.yml` run or directly. The job:

- checks out Mesa at `17ca6174dcc6cb22059ac343bc29f8af7800f42e`;
- checks out NVIDIA open-gpu-kernel-modules at `e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb`;
- applies `nvk/nvk-macos.patch` without fuzz;
- builds Mesa's `mesa_clc` and `vtn_bindgen2` host tools from that same source;
- builds `libvulkan_nouveau.dylib` (NVK) from the patched Mesa tree;
- builds `libvulkan.dylib` from Vulkan-Loader commit `a9e72c66d5cb79911eb9a9063bf4016dd0a3a123` and Vulkan-Headers commit `8864cdc896bbc2a9b6eb36b3218fc9ef57908d77`;
- downloads the NVIDIA 610.57.04 installer from `download.nvidia.com`, checks its pinned SHA-256, and extracts only the required GPU firmware and NVIDIA license; and
- records all revisions and output hashes in the runtime artifact.

The build tools installed by Homebrew and pip are CI toolchain inputs, not shipped runtime libraries. CI rejects a runtime dylib if its load commands contain a Homebrew path.

The runtime artifact is named `nullmoth-runtime-<commit>`.

## 4. Package

Run **Package unsigned release** (`.github/workflows/package-release.yml`) with the three successful run IDs and a version. The workflow requires all three runs to be successful and to have the same `head_sha`; it verifies every artifact manifest and checksum before staging the package. It emits the hand-install tarball, a 1401 app ZIP, and a DMG containing both the app and the exact checksum-bound driver tarball.

The result remains unsigned. Installing it still requires the macOS security changes described by the project, and should only be attempted on a disposable/test installation with recovery access.

## NVIDIAShared.bundle

`NVIDIAShared.bundle` is deliberately not part of this build. Its implementation and reproducible acquisition recipe are not present in the repository. It is an optional vendor-compiler path, not the NVK runtime; see [NVIDIAShared.bundle](NVIDIA-SHARED.md).
