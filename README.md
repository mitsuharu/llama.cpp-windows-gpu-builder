# llama.cpp Windows GPU Builder

Reproducible Windows x64 builds of [`llama.cpp`](https://github.com/ggml-org/llama.cpp) for NVIDIA CUDA and AMD ROCm/HIP. Both backends are compiled with `GGML_CUDA_NO_PEER_COPY=ON`.

The `llama.cpp` source is pinned as a Git submodule. GitHub Actions provisions the toolchains on disposable Windows runners, builds the binaries, and uploads ZIP artifacts. A Windows VM or Windows Sandbox can be used for an isolated local build. WSL/Docker CUDA and ROCm containers produce Linux binaries, not native Windows binaries.

## Clone

```powershell
git clone --recurse-submodules https://github.com/mitsuharu/llama.cpp-windows-gpu-builder.git
cd llama.cpp-windows-gpu-builder
```

If the repository was cloned without submodules:

```powershell
git submodule update --init --recursive
```

## GitHub Actions

Open **Actions > Build Windows GPU binaries > Run workflow**. Select one of:

- `all`: CUDA and every configured ROCm target
- `cuda`: CUDA 12.4 only
- `rocm`: ROCm 7.14 only, using the selected `gfx` target

The output is available from the workflow run as a downloadable artifact.

Default ROCm targets:

| Target | Typical hardware |
| --- | --- |
| `gfx1100` | Radeon RX 7900 series |
| `gfx1101` | Radeon RX 7800 XT / RX 7700 XT |
| `gfx1150` | Selected Ryzen AI 300 APUs |
| `gfx1151` | Selected Ryzen AI Max APUs |

Confirm the exact target for your GPU against AMD's current compatibility documentation. Windows ROCm support is narrower than Linux ROCm support.

## Local CUDA build

Prerequisites: Visual Studio 2022 Build Tools with **Desktop development with C++**, CMake, Ninja, and the CUDA Toolkit.

Run from a Developer PowerShell for Visual Studio:

```powershell
.\scripts\Build-Cuda.ps1
```

Optionally restrict the compiled CUDA architectures:

```powershell
.\scripts\Build-Cuda.ps1 -CudaArchitectures 86,89
```

## Local ROCm build

Prerequisites: CMake, GNU Make, and AMD's Windows ROCm/HIP SDK (or TheRock ROCm wheels). Activate the toolchain and ensure `HIP_PATH` points to its root, then run:

```powershell
.\scripts\Build-Rocm.ps1 -GpuTarget gfx1100
```

The GitHub workflow uses the same TheRock wheel-based environment as upstream `llama.cpp` CI.

## Package a local build

```powershell
.\scripts\Package-Build.ps1 -BuildDir .\build-cuda -Name llama-win-x64-cuda-no-peer-copy
```

## Updating llama.cpp

```powershell
git -C vendor/llama.cpp fetch origin master
git -C vendor/llama.cpp checkout origin/master
git add vendor/llama.cpp
git commit -m "chore: update llama.cpp"
```

## License

The build automation in this repository is MIT licensed. `llama.cpp` remains subject to its own license.
