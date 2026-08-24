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

GitHubリポジトリで**Actions > Build Windows GPU binaries > Run workflow**を開き、ビルド対象を選択します。

- `all`: CUDAと、選択したROCmターゲットの両方をビルド
- `cuda`: ワークフローに設定されたCUDAバージョンをビルド
- `rocm`: ワークフローに設定されたROCmバージョンを、選択した`gfx`ターゲット向けにビルド

`llama_source`では、使用する`llama.cpp`の種類を選択します。

| `llama_source` | `llama_tag`未入力時 | `llama_tag`入力例 |
| --- | --- | --- |
| `release` | 最新の安定版を自動選択 | `v0.2.0` |
| `nightly` | 最新のnightly/dev版を自動選択 | `b10603` |
| `latest-branch` | `origin/master`の最新コミット | 入力不可 |

`llama_tag`は任意です。指定した種類とタグ形式が一致しない場合や、`latest-branch`を選択してタグも入力した場合は、ビルドを開始せずエラーになります。

ビルド結果は、ワークフロー実行画面からArtifactとしてダウンロードできます。Artifact名には、実際に使用した`llama.cpp`タグまたは`master-<コミットSHA>`が含まれます。

### GitHub Releaseへの公開

ビルド済みZIPを[Releases](https://github.com/mitsuharu/llama.cpp-windows-gpu-builder/releases)にも添付する場合は、手動実行時に`publish_release`を有効にします。

- `release_tag`が空欄の場合は、`build-<llama.cppバージョン>-<実行番号>.<再実行番号>`形式の重複しないタグを生成します。
- `release_tag`を指定し、そのReleaseが存在しない場合は、新しいReleaseを作成します。
- 指定したReleaseがすでに存在する場合は、そのReleaseへZIPを追加します。同名Assetがすでに存在する場合は上書きせずエラーになります。
- CUDA／ROCmの両方をビルドした場合は、両方のZIPを同じReleaseへ添付します。
- ビルドが失敗またはキャンセルされた場合は、Releaseを作成しません。

Release作成には`GITHUB_TOKEN`の`contents: write`権限を使用します。リポジトリの**Settings > Actions > General > Workflow permissions**で、ワークフローからの書き込みが許可されていることを確認してください。

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

### ROCmでGPU推論を有効にする

ROCm 7.14のWindowsパッケージでは、`hipblas.dll`、`rocblas.dll`などの実行時DLLはllama.cppのZIPに含まれません。実行PCへR9700（`gfx1201`）対応のROCm/TheRock 7.14をインストールし、`C:\TheRock\build\bin`をPATHに追加する必要があります。

ROCm版ZIPには、実行時DLLを確認してPATHを一時設定する`Run-Rocm.ps1`を同梱します。まずGPUが認識されることを確認します。

```powershell
.\Run-Rocm.ps1 -Executable llama-cli.exe -- --list-devices
```

モデルをGPUへオフロードして実行するには、`-ngl`を指定します。`-ngl 99`は、可能な限りすべてのレイヤーをGPUへ配置します。

```powershell
.\Run-Rocm.ps1 -Executable llama-cli.exe -- -m C:\models\model.gguf -ngl 99
```

ベンチマーク結果の`backend`列が`ROCm`になっていることも確認できます。

```powershell
.\Run-Rocm.ps1 -Executable llama-bench.exe -- -m C:\models\model.gguf -ngl 99 -p 128 -n 128
```

ROCmを別の場所へインストールした場合は、`-RocmRoot`で指定します。

```powershell
.\Run-Rocm.ps1 -RocmRoot D:\ROCm -Executable llama-cli.exe -- --list-devices
```

`--list-devices`にR9700が表示されない場合は、AMDドライバー、ROCm 7.14のインストール、および`gfx1201`版ZIPを確認してください。公式の[Windows ROCm導入ガイド](https://github.com/ggml-org/llama.cpp/discussions/27047)も参照してください。

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

更新スクリプトは、引数を指定しない場合に`v0.2.0`のような安定版リリースタグを公式リポジトリから取得し、Semantic Versionが最も新しいリリースへ更新します。`b10603`のような`b`タグはnightly/dev版のため、デフォルトでは選択しません。

```powershell
.\scripts\Update-LlamaCpp.ps1
```

特定の安定版リリースを使用する場合は、[llama.cpp Releases](https://github.com/ggml-org/llama.cpp/releases)に掲載されている`vX.Y.Z`形式のタグを`-Release`で指定します。

```powershell
.\scripts\Update-LlamaCpp.ps1 -Release v0.2.0
```

`b10603`のようなnightly/dev版を使用する場合は、安定版と区別するため`-Nightly`で指定します。

```powershell
.\scripts\Update-LlamaCpp.ps1 -Nightly b10603
```

最新のnightly/dev版を自動選択する場合は、`-LatestNightly`を指定します。

```powershell
.\scripts\Update-LlamaCpp.ps1 -LatestNightly
```

リリース前の変更を含む`origin/master`の最新コミットを使用する場合は、`-LatestBranch`を明示します。

```powershell
.\scripts\Update-LlamaCpp.ps1 -LatestBranch
```

`-Release`、`-Nightly`、`-LatestNightly`、`-LatestBranch`は同時に指定できません。存在しないタグや、それぞれの形式に一致しない値を指定すると、submoduleは変更されずエラーになります。また、submodule内に未コミットの変更がある場合も更新を中止します。

更新したバージョンを親リポジトリに記録して共有するには、続けて次を実行します。

```powershell
git add vendor/llama.cpp
git commit -m "Update llama.cpp submodule"
git push
```

現在固定されているバージョンは次のコマンドで確認できます。

```powershell
git submodule status
git -C vendor/llama.cpp log -1 --oneline
```

## ライセンス

このリポジトリのビルド自動化部分にはMIT Licenseが適用されます。`llama.cpp`には、`llama.cpp`自身のライセンスが適用されます。
