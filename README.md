# llama.cpp Windows GPU Builder

NVIDIA CUDAおよびAMD ROCm/HIPに対応した、[`llama.cpp`](https://github.com/ggml-org/llama.cpp)の再現可能なWindows x64ビルド環境です。どちらのバックエンドも`GGML_CUDA_NO_PEER_COPY=ON`を指定してビルドします。

`llama.cpp`のソースコードはGit submoduleとして特定のコミットに固定しています。GitHub Actionsは使い捨てのWindows runner上にツールチェーンを準備し、バイナリをビルドしてZIP形式のArtifactをアップロードします。ローカルで隔離されたビルド環境が必要な場合は、Windows VMまたはWindows Sandboxを利用できます。WSL/DockerのCUDA・ROCmコンテナで生成されるのはLinuxバイナリであり、Windowsネイティブバイナリではありません。

## クローン

```powershell
git clone --recurse-submodules https://github.com/mitsuharu/llama.cpp-windows-gpu-builder.git
cd llama.cpp-windows-gpu-builder
```

submoduleを含めずにクローンした場合は、次のコマンドで取得します。

```powershell
git submodule update --init --recursive
```

## GitHub Actions

GitHubリポジトリで**Actions > Build Windows GPU binaries > Run workflow**を開き、次のいずれかを選択します。

- `all`: CUDAと、選択したROCmターゲットの両方をビルド
- `cuda`: ワークフローに設定されたCUDAバージョンをビルド
- `rocm`: ワークフローに設定されたROCmバージョンを、選択した`gfx`ターゲット向けにビルド

ビルド結果は、ワークフロー実行画面からArtifactとしてダウンロードできます。

選択可能なROCmターゲットは次のとおりです。

| ターゲット | 主な対応ハードウェア |
| --- | --- |
| `gfx1100` | Radeon RX 7900シリーズ |
| `gfx1101` | Radeon RX 7800 XT / RX 7700 XT |
| `gfx1150` | 一部のRyzen AI 300 APU |
| `gfx1151` | 一部のRyzen AI Max APU |
| `gfx1201` | Radeon AI PRO R9700 (RDNA 4) |

使用するGPUの正確なターゲットは、AMDの最新互換性ドキュメントで確認してください。Windows版ROCmが対応するハードウェアは、Linux版ROCmより限定されています。

## ローカルでのCUDAビルド

必要な環境は、**C++によるデスクトップ開発**を含むVisual Studio 2022 Build Tools、CMake、Ninja、およびCUDA Toolkitです。

Developer PowerShell for Visual Studioから実行します。

```powershell
.\scripts\Build-Cuda.ps1
```

必要に応じて、ビルド対象のCUDAアーキテクチャを限定できます。

```powershell
.\scripts\Build-Cuda.ps1 -CudaArchitectures 86,89
```

## ローカルでのROCmビルド

必要な環境は、CMake、GNU Make、およびAMDのWindows ROCm/HIP SDK（またはTheRock ROCm wheel）です。ツールチェーンを有効化し、`HIP_PATH`がそのルートディレクトリを指していることを確認してから実行します。

```powershell
.\scripts\Build-Rocm.ps1 -GpuTarget gfx1201
```

GitHub Actionsでは、公式`llama.cpp` CIと同じTheRock wheelベースの環境を使用します。

## ツールチェーンのバージョン更新

CUDAとROCmのバージョンは、`.github/workflows/build-windows-gpu.yml`のトップレベルにある`env`ブロックで一元管理しています。

```yaml
env:
  CUDA_VERSION: '12.4'
  ROCM_VERSION: '7.14.0'
```

ツールチェーンを更新する場合は、次の手順を実施します。

1. トップレベルの`env`ブロックにある該当バージョンだけを変更します。
2. CUDAの場合は、`vendor/llama.cpp/.github/actions/windows-setup-cuda/action.yml`に新しいバージョンのインストール処理が存在することを確認します。必要であれば、先に`llama.cpp` submoduleを更新します。
3. ROCmの場合は、AMDの`rocm/whl-multi-arch`パッケージインデックスで対象バージョンが公開されていることを確認します。
4. GitHub Actionsから変更したバックエンドだけを実行し、バックエンドDLLとバージョン付きZIP Artifactが生成されることを確認します。

各ジョブ内に同じバージョン値を重複して定義しないでください。セットアップ処理とArtifact名は、トップレベルの共有変数を自動的に参照します。

## ローカルビルドのパッケージ化

```powershell
.\scripts\Package-Build.ps1 -BuildDir .\build-cuda -Name llama-win-x64-cuda-no-peer-copy
```

## llama.cppの更新

```powershell
git -C vendor/llama.cpp fetch origin master
git -C vendor/llama.cpp checkout origin/master
git add vendor/llama.cpp
git commit -m "chore: update llama.cpp"
```

## ライセンス

このリポジトリのビルド自動化部分にはMIT Licenseが適用されます。`llama.cpp`には、`llama.cpp`自身のライセンスが適用されます。
