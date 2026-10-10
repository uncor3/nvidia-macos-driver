# Building unsigned artifacts

Run **Build and package unsigned driver** (`.github/workflows/build.yml`). This is the only workflow: its components, kexts, and runtime jobs build in parallel, and its package job waits for all three to succeed. Every job uses the same source commit. Nothing produced here is signed or notarized.

Pushes to `main`, pull requests, and manual runs all build and package the complete driver. A manual run accepts a package version such as `1.0.14`; automatic runs use `0.0.<run-number>`. There are no separate workflow runs or run IDs to enter.

## 1. Project components

The `build` job builds the repository-owned Metal driver, AIR-to-SPIR-V translator, EFI helper, and installer application. Its intermediate artifact is named `nullmoth-unsigned-<commit>`.

## 2. Kernel extensions

The `kexts` job builds the kexts against the pinned NVIDIA open-gpu-kernel-modules source, including both macOS 15 and 26 NVAccel variants. Its intermediate artifact is named `nullmoth-kexts-<commit>`.

Before compiling, the workflow applies `build/patches/ogkm-darwin-version.patch` to the pinned NVIDIA checkout. This narrowly allows `NV_DARWIN` in the platform guards of `nvVer.h` and `nvUnixVersion.h`, preserving NVIDIA's own version metadata without enabling Linux-specific code. Direct use of `build/build_kexts_ci.sh` requires the same patch in its `OGKM` tree. This addresses the observed version-header errors; the complete kext build and hardware behavior still require validation.

## 3. User-space runtime and firmware

The `runtime` job:

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

The `package` job downloads the three intermediate artifacts from its own workflow run and verifies every artifact manifest and checksum before staging the package. It emits the hand-install tarball, a 1401 app ZIP, and a DMG containing both the app and the exact checksum-bound driver tarball. It then extracts the tarball into a temporary directory, verifies the payload checksums and required files, and confirms that the executable install/uninstall scripts match this checkout. It never installs or loads the driver in CI.

Download **`nullmoth-release-<version>-<commit>`** for the complete package. The other three artifacts are intermediate build outputs, not complete installers. The final package uses this run's source-built binaries and official NVIDIA firmware; no binaries are downloaded from nullmoth's releases.

## 5. Manual offline installation

Transfer the final tarball to the target macOS machine. Extract it into a fresh directory, then:

```bash
tar -xzf nullmoth-nvidia-VERSION.tar.gz
cd pkgroot
shasum -a 256 -c SHA256SUMS
sudo bash ./install.sh
```

The archive contains `install.sh`, `uninstall.sh`, all four kexts with both NVAccel variants, the Metal/Vulkan runtime and configuration, and NVIDIA firmware. The installer takes its files from this local `pkgroot`, selects the accelerator for the current macOS version, and performs its kernel-collection preflight before installing. Neither installer script downloads anything. No app or DMG is required for manual installation.

Configure OpenCore separately as described in the repository README before rebooting. The kexts are installed into `/Library/Extensions`, not injected through `EFI/OC/Kexts`. The installer does not configure OpenCore for you.

To remove the installed driver, use the same package's script on macOS:

```bash
sudo bash ./uninstall.sh
```

Both installation and removal require a reboot. Compilation and package validation do not establish hardware compatibility or successful loading on the target machine.

The result remains unsigned. Installing it still requires the macOS security changes described by the project, and should only be attempted on a disposable/test installation with recovery access.

## NVIDIAShared.bundle

`NVIDIAShared.bundle` is deliberately not part of this build. Its implementation and reproducible acquisition recipe are not present in the repository. It is an optional vendor-compiler path, not the NVK runtime; see [NVIDIAShared.bundle](NVIDIA-SHARED.md).
