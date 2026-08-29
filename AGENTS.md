# Repository instructions

## Purpose

- This repository builds reproducible Windows x64 `llama.cpp` packages for CUDA, ROCm, and Vulkan.
- CUDA and ROCm builds use `GGML_CUDA_NO_PEER_COPY=ON` to favor stability in multi-GPU environments.
- ROCm release ZIPs must be self-contained enough to run without a separately installed ROCm SDK.

## Git workflow

- Do not commit directly to `main`.
- Create a dedicated branch for each change and finish the work with a pull request.
- Before editing, inspect the current branch, worktree status, and existing user changes.
- Preserve unrelated changes. Never reset, discard, or overwrite them without explicit user approval.
- Keep commits focused and describe the reason for non-obvious build or packaging changes.
- Do not update the `vendor/llama.cpp` submodule unless the task explicitly requires it.

## GitHub Actions

- Keep pull-request CI lightweight. PR CI should perform syntax checks and the minimal Windows CPU smoke build only.
- Do not download GPU SDKs, build GPU backends, publish artifacts, or create Releases from PR CI.
- Use caching for downloaded SDKs and expensive build outputs. Cache keys must include every value that can make cached output incompatible, including toolchain version, ROCm target, source revision, runner context, and relevant build scripts.
- Keep toolchain versions selectable from `workflow_dispatch` and pass the selected values consistently to setup, cache keys, artifact names, and Release metadata.
- Release creation must remain limited to an explicitly supported release-producing event. A future automatic upstream-release trigger must update the Release job guard deliberately.
- Pin third-party GitHub Actions to immutable commit SHAs and retain a version comment.

## ROCm

- ROCm 7.14 wheels use `https://repo.amd.com/rocm/whl-multi-arch/`.
- ROCm 10 and later stable wheels use `https://stable.repo.amd.com/rocm/whl-next/`.
- Install the SDK libraries, development files, and selected `device-gfx*` package from the matching index.
- Fail immediately if wheel installation fails; do not continue to `rocm-sdk init` after a failed install.
- Keep ROCm SDK and build caches separated by ROCm version and GPU target.
- A self-contained ROCm ZIP must include required runtime DLLs, the selected device kernels, rocBLAS data, and applicable licenses.
- Treat Windows system DLL and delay-load dependency reports separately from missing redistributable ROCm runtime files.

## Packaging and naming

- Include the selected `llama.cpp` reference and backend toolchain version in ZIP artifact names.
- Include the ROCm version and `gfx` target in ROCm artifact and Release names.
- CUDA package names must state that peer copy is disabled.
- Keep Release titles and notes aligned with the actual uploaded ZIPs.

## Validation

- After changing a PowerShell script, parse it with `System.Management.Automation.Language.Parser`.
- Run `git diff --check` before committing.
- Let the pull-request `windows-smoke` check complete before merging.
- For changes to GPU setup, compilation, caching, or packaging, run the affected backend manually through `Build Windows GPU binaries` before merging when practical.
- Verify that cache keys, artifact names, and Release metadata change when a selected version or ROCm target changes.

## Documentation

- Update `README.md` when user-facing workflow inputs, supported versions or targets, package contents, or operating instructions change.
- Keep temporary task state, current PR numbers, credentials, and one-off debugging logs out of this file. Use Git history, pull requests, and issues for that information.
