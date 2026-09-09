# Android 16 + patched WebView on an Apple Silicon Mac

Status on 2026-09-09: built and running on this Mac. Android 16/API 36 arm64
boots with the complete patched Chromium 154 WebView. Ordinary create/get and
conditional get succeeded with the authorized test provider. The unmodified WebView control reports
conditional unavailable and ordinary get returns `Not implemented`. One initial
conditional assertion failed challenge verification; a later retry succeeded.
The initial failure and a reload that did not show a picker remain recorded;
repeated reliability is not established. All GCP VMs and disks were deleted and
the final execution audit is clean.

The [combined investigation report](../../docs/android16-macos-passkeys.md) also
covers the two Lightning APKs and their 2026-09-10 comparison on
passkeys-debugger.io, with public evidence and the limits of each validation.

## このMacで確認する

現在 `aospman_android16`（`emulator-5560`）が起動しており、パッチ適用版の
WebViewとテスト用パスキープロバイダが設定済みです。エミュレータを閉じた後は、
次のファイルをFinderからダブルクリックするか、ターミナルで実行してください。
既存の `medium_phone` AVDは変更していません。

```sh
/Users/yusuke-iwaki/src/github/YusukeIwaki/aospman/artifacts/android16-macos-emulator-20260908/launch.command
```

ホーム画面からブラウザを開く場合は、次のコマンドも使えます。

```sh
/Users/yusuke-iwaki/Library/Android/sdk/platform-tools/adb -s emulator-5560 shell am start -n \
  com.example.webviewpasskeybrowser.browser/com.example.webviewpasskeybrowser.MainActivity
```

1. 現在の認証済みページを下へスクロールし、「ログアウトして再テスト」を押します。
2. ログインフォームまでスクロールし、空のユーザー名欄をタップすると条件付き認証の候補が出ます。
3. 保存したパスキーを選び、Continue、端末PINの順に進むと認証済みページへ戻ります。
4. 通常ログインは、候補画面を閉じ、テストユーザー名を入力して「パスキーでログイン」を押します。

この専用AVDに設定したテストユーザー名とPINは、成果物ディレクトリの
`local-test-config.json` に保存しています（権限0600）。個人端末のPINではありません。
再利用する場合はAVDのデータを消去しないでください。PIN画面のスクリーンショットが
黒くなるのは通常の保護動作です。ソフトキーボードはハードウェアキーボード設定により
表示されない場合がありますが、Macのキーボードで入力できます。

初回の条件付き認証ではチャレンジ不一致が1回あり、その後の通常ログインと、
ログアウト後の条件付き認証は成功しました。詳細と証拠は
`artifacts/android16-macos-emulator-20260908/investigation.md` にあります。
Google Password Managerの承認やChrome Password ManagerのUIは今回の検証対象に含みません。

The Linux build host cross-compiles arm64 Android binaries. macOS runs the
resulting Android Emulator image. AOSP and Chromium's Android build do not
support a native macOS build host.

## Pinned inputs

| Input | Revision / target |
| --- | --- |
| AOSP manifest | `android-16.0.0_r4`, commit `15128c9e27cfa599c48d294babd39286ee8f1426` |
| AOSP product | `sdk_phone64_arm64-aosp_current-userdebug` |
| Chromium | `98596990901c11e89a24f6217f1b66513b065026`, version `154.0.8016.0` |
| Chromium target | `system_webview_64_apk`, `target_cpu="arm64"` |
| Feature patch | `patches/chromium-webview-browser-conditional.patch`, SHA-256 `d6c264ac07a3d80d2d2dba065ba36cc06bad64cb4c1d3eda714aeb9cad815907` |
| AOSP integration | `patches/aosp-android16-preserve-webview-signature.patch` |

The integration preserves the full Chromium APK and its signature through
AOSP's supported `presigned`/`preprocessed` import. Soong's APK validation stays
enabled. The import also declares the APK's three optional libraries in exact
manifest order (`android.test.base`, `androidx.window.extensions`,
`android.ext.adservices`). The original AOSP declaration omitted test-base and
listed an XR library absent from this Chromium APK; strict validation caught
that mismatch and the import definition was corrected. The image contains the treatment WebView. An unmodified same-revision,
same-signature control APK can be installed as an update for comparison and then
replaced by the treatment. This avoids changing the system image between cases.

The legacy Android 17 Cuttlefish pstore, V4L2, and Advanced Protection workarounds
are not applicable to the Android 16 Goldfish emulator target. The old Mockito
matcher patch belongs to the superseded prototype, not the current refactor.

## Cloud build sequence

Follow the repository's `manage-aosp-spot-build` skill. The quota observed on 2026-09-08 admitted
`n2-highcpu-32`, but not the standard 90/96-vCPU profiles, and permitted a maximum
500 GB `pd-balanced` disk. This constrained resource choice was explicitly approved by the user.

Use one Spot VM at a time in `aospman`, zone `asia-northeast1-b`, with an 8-hour
maximum run duration, automatic instance and boot-disk deletion, management
labels, no service account, and no OAuth scopes. Use separate fresh VMs for the
two stages so the 500 GB disk does not contain both checkouts simultaneously.

1. Run `spot-vm.sh audit`, then `spot-vm.sh preflight constrained`.
2. Create/bootstrap `aospman-webview-arm64-20260908` with profile `constrained`,
   lifetime `8`, disk `500` using `spot-vm.sh`. Wait for `sudo cloud-init status --wait`
   to report completion before bootstrap, so first-boot apt configuration cannot race it.
3. Copy `build-webview.sh` and the feature patch into an input directory on that
   VM. Run `bash build-webview.sh INPUT_DIRECTORY` and retain the SSH output
   locally. The script exports `/work/export/webview/` progressively.
4. Copy each finished APK immediately, verify its SHA-256 locally, and retain
   logs, source/dependency revisions and GN args. Verify that both APKs are
   `arm64-v8a`, have target SDK 36 and the same signing certificate.
5. Delete the exact WebView VM and its disk; audit again.
6. Create/bootstrap `aospman-android16-arm64-20260908` with the same resource
   limits. Copy `build-aosp.sh`, the treatment APK,
   `aosp-webview-integration.patch` (a copy of the repository integration patch),
   and `treatment.sha256` into its input directory. The hash file must contain
   the actual APK SHA-256 and the filename `treatment-SystemWebView64.apk`.
7. Run `bash build-aosp.sh INPUT_DIRECTORY`. It builds Android 16, packages the
   QEMU images, preserves the resolved manifest, and verifies that the integrated
   provider APK is byte-identical to the Chromium output. It uses 32 GiB of
   temporary swap on the auto-deleting disk and starts at 12 jobs. In this run,
   memory/CPU measurements justified resuming at 20 jobs with
   `AOSPMAN_BUILD_JOBS=20 ... --resume-build`; the high-memory pool remains two
   jobs. The script accepts 1–24 jobs and rechecks the existing patch/APK on resume.
8. Copy `/work/export/aosp/` artifacts (archive, integrated APK, manifest,
   hashes, patches and logs) locally, hash-verify them, delete the VM/disk, and
   run the final audit. The initial userdata comes from the built product
   output (`userdata.img`, raw ext4), alongside `advancedFeatures.ini` and
   `encryptionkey.img`. Source trees and build intermediates are disposable.

Build scripts deliberately refuse to overwrite an existing work directory.
After an interrupted build, inspect the log and resume its unfinished command
within the original checkout; do not restart the script blindly. For a verified
stopped sync failure, `build-aosp.sh INPUT_DIRECTORY --resume-sync` resumes
sync with bounded retries at 8, 4, then 2 jobs. If interruption left partial
checkouts, `--repair-sync` additionally forces checkout; use it only after
confirming that this disposable source tree contains no local work. Sync does
not use fail-fast, so one failed fetch does not interrupt other checkouts. Do not extend
the VM deadline or lose completed artifacts while waiting for another stage.

## Local launch and validation from exported artifacts

Extract `aosp/android16-arm64-image.tar.gz` to `aosp/image/`, alongside
`aosp/image-SHA256SUMS`, then run from the repository:

```sh
tools/android16-macos/start-emulator.sh /absolute/path/to/aosp/image
```

The launcher creates a separate `aospman_android16` AVD with 4 vCPUs, 4 GiB RAM,
8 GiB writable data, and adb serial `emulator-5560`. Existing AVDs are preserved.
It checks all image hashes before registering or starting the AVD. Reuse preserves
the AVD data; close the current emulator before launching another copy.

Record `ro.build.fingerprint`, `ro.build.version.sdk`, `ro.product.cpu.abi`,
`sys.boot_completed`, and `dumpsys webviewupdate`. This run's results are in
`evidence/initial-device.txt`. The integrated system APK is
`/product/app/webview/webview.apk`; its SHA-256 equals treatment below.

For a fresh AVD, install the preserved browser/provider fixtures after verifying
the signatures in the investigation record. Enable the test provider and use
Settings to configure a test-only screen lock on that fresh lab AVD:

```sh
artifact_root=/absolute/path/to/artifacts/android16-macos-emulator-20260908
adb_bin="$HOME/Library/Android/sdk/platform-tools/adb"
"$adb_bin" -s emulator-5560 emu avd name  # Must be aospman_android16.
"$adb_bin" -s emulator-5560 install "$artifact_root/apks/webview-passkey-browser-browser-query-debug.apk"
"$adb_bin" -s emulator-5560 install "$artifact_root/apks/aospman-test-credential-provider-debug.apk"
provider_component=com.example.aospman.passkeyprovider/com.example.android.authentication.myvault.data.MyVaultService
"$adb_bin" -s emulator-5560 shell settings put secure credential_service "$provider_component"
"$adb_bin" -s emulator-5560 shell settings put secure credential_service_primary "$provider_component"
```

The current Mac AVD already has these apps, provider settings and a test lock.
Use the adb debugging skill for observe/action/capture UI steps. The RP is
`https://passkey-test-lab-production.up.railway.app/`.

## Control/treatment switch on the same image

Use the same browser, provider and saved passkey. Do not clear their data.
The APK signatures and versions match, allowing replacement as a normal update.

```sh
artifact_root=/absolute/path/to/artifacts/android16-macos-emulator-20260908
adb_bin="$HOME/Library/Android/sdk/platform-tools/adb"
"$adb_bin" -s emulator-5560 emu avd name  # Must be aospman_android16.
"$adb_bin" -s emulator-5560 shell am force-stop com.example.webviewpasskeybrowser.browser
"$adb_bin" -s emulator-5560 install -r -d "$artifact_root/chromium/control-SystemWebView64.apk"
"$adb_bin" -s emulator-5560 shell dumpsys webviewupdate
"$adb_bin" -s emulator-5560 shell pm path com.android.webview
# Hash the returned base.apk path with adb shell sha256sum; it must match below.
"$adb_bin" -s emulator-5560 shell am start -n \
  com.example.webviewpasskeybrowser.browser/com.example.webviewpasskeybrowser.MainActivity
```

Repeat with `treatment-SystemWebView64.apk` to restore the treatment and verify
its hash. Both report `com.android.webview`, version `154.0.8016.0` / `801600001`;
version alone cannot distinguish them. Current final state is treatment.

| APK | SHA-256 |
| --- | --- |
| Control | `fcfa19c150cd8177c355f8062a98c9bb2a7d6d4acdbf5c6397afd4ddb02c73a6` |
| Treatment | `bf0c5f74c1275d622ecca1f0bf7a8e180fd50ad2a8a1da892809c310fcbfc914` |

The browser app's fixed title says “BROWSER treatment” in both cases; it names
the app flavor, not the installed WebView patch variant. Its `conditionalApi:
true` header means the method exists. Use the asynchronous console result
`AOSPMAN_CONDITIONAL_AVAILABLE false/true` and the RP Autofill badge for actual
conditional availability. Control/treatment installation hashes, UI evidence,
redacted logcat and a passive network record are preserved under `evidence/`.

The final source-build and runtime record is
`artifacts/android16-macos-emulator-20260908/investigation.md`. Chronological
build recovery is in `execution-journal.md`. `gcp-execution-final-audit.txt` is
the authoritative clean audit; the similarly named `gcp-final-audit.txt` is a
historical preparation snapshot. Binary artifacts and records are locally
durable but excluded by `.git/info/exclude`; keep the artifact directory when
moving or archiving this environment.
