# Lightning browser passkey experiment

Upstream: https://github.com/anthonycr/Lightning-Browser.git

Pinned commit: `6b222ad616d4563f2b3a5b8a37e33b3e4042de28`.
Built flavor: `lightningPlusDebug`, version `5.1.0` / `102`.

`lightning-browser-passkey.patch` enables AndroidX WebKit browser-mode WebAuthn
on each browsing WebView after checking feature support, and declares
`CREDENTIAL_MANAGER_SET_ORIGIN` and
`CREDENTIAL_MANAGER_QUERY_CANDIDATE_CREDENTIALS`. Upstream already enables
Android Autofill and depends on AndroidX WebKit 1.17.0; those stay unchanged.
The patch also adds `.passkey` to the application ID, sets the launcher label to
`Lightning.passkey`, and separates task affinities for side-by-side installation.
The namespace and activity class names stay the same.

This app patch relies on a WebView with conditional mediation support. The
experiment uses the existing Chromium 154 patch and Android 16 AOSP image from
`artifacts/android16-macos-emulator-20260908/`. It does not make stock WebView
support conditional mediation or grant Google Password Manager approval.

`test-provider-lightning-allowlist.patch` is a separate patch against this
repository's `test-credential-provider/`. It adds the exact control and treatment
package/signature pairs to our authorized test provider while keeping validation
and existing entries. It pins this lab's debug certificate; a different signing
key needs its own explicit provider configuration. It does not alter GPM policy.

## Build the two APKs

Use a full JDK 21 including `jlink` and the Android SDK. The verified local JDK is
`~/.local/share/aospman/jdks/jdk-21.0.12.1+1/Contents/Home` (Temurin).
PyCharm's bundled JBR 21 lacks `jlink` and cannot run this AGP build.
Upstream pins Gradle 9.7.1, AGP 9.4.0,
compile SDK 37.1, build-tools 37.0.0 and target SDK 37 (min SDK 28).
The APKs run on the existing API 36 emulator without changing target SDK.

```sh
git clone https://github.com/anthonycr/Lightning-Browser.git lightning-control
cd lightning-control
git checkout --detach 6b222ad616d4563f2b3a5b8a37e33b3e4042de28
# Set JAVA_HOME to JDK 21 and ANDROID_HOME to the Android SDK.
./gradlew :app:assembleLightningPlusDebug --max-workers=4 --console=plain
# Copy app/build/outputs/apk/lightningPlus/debug/app-lightningPlus-debug.apk
# to a durable control APK path before proceeding.
git worktree add --detach ../lightning-passkey HEAD
cd ../lightning-passkey
git apply --check /absolute/path/to/aospman/patches/lightning-browser-passkey.patch
git apply /absolute/path/to/aospman/patches/lightning-browser-passkey.patch
./gradlew :app:assembleLightningPlusDebug --max-workers=4 --console=plain
# Copy the corresponding APK to a durable treatment APK path.
```

The original control source has no tracked changes. SDK paths in local.properties
are machine-local, ignored build configuration. Both APKs use the same local
debug signing identity. Control is `acr.browser.lightning` / `Lightning`;
treatment is `acr.browser.lightning.passkey` / `Lightning.passkey`.

## Install and launch

Verify `adb -s emulator-5560 emu avd name` is `aospman_android16` first and unlock
the saved AVD normally after a cold boot. Install
the control and treatment APKs with `adb -s emulator-5560 install -r APK_PATH`.
Launch a specific one using its explicit component:

```sh
adb -s emulator-5560 shell am start -a android.intent.action.VIEW \
  -d https://passkey-test-lab-production.up.railway.app/ \
  -n acr.browser.lightning/acr.browser.lightning.DefaultBrowserActivity
adb -s emulator-5560 shell am start -a android.intent.action.VIEW \
  -d https://passkey-test-lab-production.up.railway.app/ \
  -n acr.browser.lightning.passkey/acr.browser.lightning.DefaultBrowserActivity
```

Use the authorized test provider with the exact APK signing certificate. Test
ordinary create/get and empty-field conditional get separately. Existing lab
PIN/account configuration is in this experiment directory's private
`local-test-config.json`; do not include it in shared logs.

The provider patch applies to aospman commit
`1253fb57c22d1cd739484398a2c15bdf0cc8d637`. In a clean checkout, apply it before
building `test-credential-provider/` with JDK 17:

```sh
git apply --check patches/test-provider-lightning-allowlist.patch
git apply patches/test-provider-lightning-allowlist.patch
cd test-credential-provider
./gradlew :app:assembleDebug :app:testDebugUnitTest --max-workers=2 --console=plain
adb -s emulator-5560 install -r app/build/outputs/apk/debug/app-debug.apk
```

The current working copy already contains the provider change. Both Lightning
APK certificates are SHA-256
`d6b890eca6f4708aff24be19176c56afee38d8d4d5612a9964f5f581ccc2b4b1`.
Preserve the existing provider signing identity when updating it in place.

## Verified result on 2026-09-09

Both APKs are installed side by side on this Mac's Android 16 AVD.

| Case | WebAuthn API | Ordinary create/get | Passkey Autofill |
| --- | --- | --- | --- |
| Upstream `Lightning` | `PublicKeyCredential` undefined | Get failed with Web Authentication service error; create not attempted | No candidate on empty-field focus |
| `Lightning.passkey` | Available | Both completed, with RP verification | Empty-field focus opened saved-passkey picker; selection and device authentication completed RP login |

Treatment `isConditionalMediationAvailable()` resolved to `true`. These results
use the existing patched Chromium WebView and authorized test provider. They do
not establish stock-WebView conditional support, GPM approval, or Chrome Password
Manager integration. Browser-mode and permission changes were tested together;
this is not an individual-permission ablation.

The [2026-09-10 comparison on passkeys-debugger.io](../docs/android16-macos-passkeys.md)
also exercised both APKs: control creation and conditional get returned
`NotSupportedError`; treatment creation and empty-field conditional get returned
credentials. The returned assertion signature was verified locally. The report
separates this from RP-server login verification and documents the debugger's
independently generated preview challenge.

Current runtime results, exact APK hashes, screenshots and build logs are in
`artifacts/lightning-passkey-20260909/investigation.md`. That record is the
authority for what was actually tested. No cloud resources are used for this
app-only experiment.
