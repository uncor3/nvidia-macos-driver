# NVIDIAShared.bundle

`NVIDIAShared.bundle` is an optional user-space compiler plug-in expected at:

```text
/Library/GPUBundles/NVIDIAShared.bundle/Contents/MacOS/NVIDIAShared
```

The repository does not contain its source, a verifiable build recipe, or a pinned official download. For that reason the source-build workflows neither fetch nor package it.

## What the checked-in code expects

`plugin/NVMTLVendorCompiler.m` attempts to load the bundle only when the `NVMTL_VENDOR_COMPILER` environment variable is present and the GPU passes its support check. It then looks up these exported functions:

- `MTLCompilerCreate`
- `NVSCompileAIRText`
- `MTLCompilerReleaseReply` (optional)

That path appears to compile textual Apple AIR through NVIDIA's compiler stack, producing PTX/cubin data that the driver can feed into the NVIDIA execution path.

The default path is separate: the repository's Rust translator converts AIR to SPIR-V and the source-built NVK/NAK stack compiles it for the GPU. Therefore `NVIDIAShared.bundle` is not required for the default driver path and is not a substitute for `libvulkan_nouveau.dylib`.

## What is known about air2nvvm.py

The previous build notes described an `air2nvvm.py` file as being inside the bundle. No checked-in executable code invokes that filename, and this repository provides neither the script nor evidence sufficient to reproduce it. That claim should be treated as a description of an external release payload, not as a buildable repository component.

## Security implication

This is native code that would be loaded into a process using the Metal plug-in. An opaque copy would therefore have the privileges of that process and would undermine a source-only build. Do not copy it from an old release merely to make the package layout match. If its source and provenance become available later, it should be reviewed and built as a separately auditable optional artifact.
