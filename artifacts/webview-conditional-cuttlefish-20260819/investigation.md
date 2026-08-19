# Patched WebView conditional passkey on AOSP Cuttlefish

- Date: 2026-08-19
- Status: complete
- Hypothesis: On API 34+ AOSP userdebug, a BROWSER-mode WebView patched to use Credential Manager prefetch for conditional mediation will report conditional mediation available and dispatch a focused-field request to an authorized test CredentialProvider, whereas the unpatched WebView does not expose conditional mediation. This hypothesis was confirmed on the pinned Android 17 Cuttlefish image.

## Question and scope

Can a small Chromium WebView change make `mediation: "conditional"` available in AndroidX WebKit BROWSER mode and route the focused-field request through Android Credential Manager on API 34+? The device experiment must keep four results separate: ordinary WebAuthn, browser-origin delegation, provider trust, and conditional/autofill UI. Because an AOSP image has no Google Password Manager, an authorized test `CredentialProviderService` is in scope; Google-provider approval and Chrome Password Manager UI are explicitly out of scope for the treatment.

## Configuration

### Local and upstream revisions

- Local repository: `git@github.com:YusukeIwaki/aospman.git`, starting commit `a4f7863ae52c91e31dd525be9a843cb055a74d7d` with pre-existing uncommitted investigation/app work preserved.
- Chromium source: `https://chromium.googlesource.com/chromium/src.git` at `e807462122f5935c440b9bd4a9721e1cb8ac6e4e` (2026-08-18T19:52:10-07:00, version `154.0.8011.0`, shallow checkout).
- AOSP source: `https://android.googlesource.com/platform/manifest` branch `android-latest-release`, resolved on 2026-08-19 to `android17-release`; manifest checkout `ad156f32caaa06dae91c02d443f6a8fe210eaa54`. The exact multi-repository revision map is preserved as `records/aospman-artifacts/aosp/aosp-manifest.xml` (SHA-256 `a97bb91ebe99656ae59f87cfb2059932c477c679b1f27287651cdeadde892bc1`). Build target: `aosp_cf_x86_64_only_phone-aosp_current-userdebug`, build ID `CP2A.260605.016`, build number `aospman-20260819`.
- Cuttlefish Debian-package source: `https://github.com/google/android-cuttlefish` at `a318f97e7094a2df11a3f9c372bf6a6f63bb3c02` (package version `1.57.0`). The final AOSP-built `cvd-host_package.tar.gz` used `platform/device/google/cuttlefish` commit `283645aacf6cdb56cc31a9362f54d412dbc132a1` from the pinned manifest.
- Framework source used by the boot workaround and permission analysis: `platform/frameworks/base` commit `94b4c163b7dfe5ce3607f7bb8456f9573f7de57d`.
- Source-change target: current Chromium `components/webauthn/android` BROWSER-mode conditional mediation path. The mode remains BROWSER; CHROME and CHROME_3PP modes are not used.

### Device, apps, and provider

- Tested device: x86_64 AOSP Cuttlefish `userdebug`, API 37, fingerprint `generic/aosp_cf_x86_64_only_phone/vsoc_x86_64_only:17/CP2A.260605.016/eng.yusuke:userdebug/test-keys`, physical display `720x1280`.
- Browser under test: `com.example.webviewpasskeybrowser.browser`, using AndroidX WebKit `WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER` and declaring both `android.permission.CREDENTIAL_MANAGER_SET_ORIGIN` and `android.permission.CREDENTIAL_MANAGER_QUERY_CANDIDATE_CREDENTIALS`.
- Final tested browser APK SHA-256: `80febc1d8a4e37f5b92dde70db0d56ae05d91068785f7b52213cbd8f40af06df`; signing-certificate SHA-256: `d6b890eca6f4708aff24be19176c56afee38d8d4d5612a9964f5f581ccc2b4b1`. The earlier APK `7f595256...` lacked the query-candidate permission and is retained only as negative diagnostic evidence. The DEFAULT-mode control package is `com.example.webviewpasskeybrowser.control`, APK SHA-256 `e6813e3a15ae41f18c5d5f34233b16d067f6ead4799ffe04f45e2e49529eb50f`.
- Provider treatment: `com.example.aospman.passkeyprovider`, adapted from Android's `identity-samples` MyVault at commit `d9adcb9fc581800b3f44f26e974b1e6fc806ee5d`. The provider locally authorizes only `com.example.webviewpasskeybrowser.browser` signed by SHA-256 certificate `D6:B8:90:EC:A6:F4:70:8A:FF:24:BE:19:17:6C:56:AF:EE:38:D8:D4:D5:61:2A:99:64:F5:F5:81:CC:C2:B4:B1`; it does not alter or bypass Google Password Manager policy.
- Provider APK: `aospman-test-credential-provider-debug.apk`, min/target API 34/35, APK SHA-256 `a7e4809a1df0aeb79466916796e8abaef523ee720ba11122a3a9336e769eb157`, signing-certificate SHA-256 `718ee94d925d8fb9e560909b56e15cf526d49cf07a732cf6f513619398b1b0b2`.

### Relying party

- Origin: `https://passkey-test-lab-production.up.railway.app/`
- RP ID: `passkey-test-lab-production.up.railway.app`

## Experiment design

| Case | Control or treatment | Expected falsifier | Result |
| --- | --- | --- | --- |
| Unpatched Chromium 154 WebView, BROWSER mode, conditional get | Control | Conditional mediation is reported available and reaches the provider without the Chromium change | `isConditionalMediationAvailable()` returned `false`; no conditional UI was exposed. |
| Patched Chromium 154 WebView, same image/browser/provider/RP, conditional get | Treatment | Availability remains false or no prefetch/focus request reaches the provider | Returned `true`; prepare-get reached the provider and focusing `login-username` opened the provider-backed Credential Manager UI. |
| Patched WebView with test provider, explicit create | Treatment | Provider dispatch succeeds but the RP never accepts a cryptographically valid WebAuthn response | Passkey creation completed, the RP accepted the response, and `/account` showed one registered passkey. |
| Patched WebView with test provider, conditional get | Treatment | A candidate appears but the provider/RP cannot finish assertion verification | Selecting the candidate and confirming PIN completed `onFinalResponseReceived`; the RP returned the authenticated account page. |

## Reproduction

```sh
# Build/install the final browser APK after applying the manifest change.
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ./webview-passkey-browser/gradlew -p webview-passkey-browser \
  :app:assembleBrowserDebug :app:testBrowserDebugUnitTest

# Launch the preserved Cuttlefish image/host package. The two environment-gated
# workarounds are only for this nested-QEMU Android 17 test image.
export AOSPMAN_DISABLE_QEMU_PSTORE=1
launch_cvd --daemon --resume=false --use_overlay=false \
  --report_anonymous_usage_stats=n --vm_manager=qemu_cli \
  --cpus=8 --memory_mb=8192 --start_webrtc=false \
  --gpu_mode=guest_swiftshader --enable_wifi=false \
  --enable_host_bluetooth=false --enable_host_uwb=false --enable_virtiofs=false

adb shell locksettings set-pin "$TEST_PIN"
adb install -r apks/aospman-test-credential-provider-debug.apk
adb install -r apks/webview-passkey-browser-browser-query-debug.apk
adb shell settings put secure credential_service \
  com.example.aospman.passkeyprovider/com.example.android.authentication.myvault.data.MyVaultService
adb shell settings put secure credential_service_primary \
  com.example.aospman.passkeyprovider/com.example.android.authentication.myvault.data.MyVaultService

# The AOSP preinstalled WebView has a different signature. On this userdebug-only
# image, replace its exact resolved path once, reboot, then install the treatment
# as the same-signed update over the control.
adb root
adb disable-verity
adb reboot
adb wait-for-device
adb root
adb remount
adb push chromium/control-SystemWebView64.apk /product/app/webview/webview.apk
adb shell chmod 0644 /product/app/webview/webview.apk
adb shell restorecon /product/app/webview/webview.apk
adb reboot
adb wait-for-device

# Capture control, then apply treatment and repeat on the same image/data.
adb install -r -d chromium/patched-SystemWebView64.apk
adb shell am start -W -n \
  com.example.webviewpasskeybrowser.browser/com.example.webviewpasskeybrowser.MainActivity
```

## Observations and evidence

- At Chromium `e8074621`, `components/webauthn/android/java/src/org/chromium/components/webauthn/AuthenticatorImpl.java` (`makeCredential`, `getAssertion`, `couldSupportConditionalMediation`) rejects make/get and conditional availability when GMS Core is unavailable before it can use WebView's API-34 Credential Manager path.
- `components/webauthn/android/java/src/org/chromium/components/webauthn/Fido2CredentialRequest.java` (`continueGetCredentialRequestAfterRpIdValidation`) explicitly returns `NOT_IMPLEMENTED` for every non-Chrome conditional request, while ordinary non-Chrome requests already use `CredManSupportProvider.getCredManSupportForWebView()`.
- The same file's `getBridge()` returns a bridge only for Chrome modes. However, `components/android_autofill/browser/android_autofill_provider.cc` (`AndroidAutofillProvider`) already obtains `WebAuthnCredManDelegate` on `autocomplete="webauthn"` fields and triggers its stored Credential Manager request when the field is focused.
- `components/webauthn/android/webauthn_cred_man_delegate.cc` (`WebAuthnCredManDelegate::GetForFrame`) intentionally returns no delegate until the embedder installs a `WebAuthnClientAndroid`. Android WebView does not install one at this revision. The treatment therefore adds `android_webview/browser/AwWebAuthnClientAndroid` and initializes it from `AwBrowserProcess`; its generic inherited Credential Manager callbacks feed the existing Android Autofill provider without adding Chrome UI code.
- At AOSP `frameworks/base` current source, `android.permission.CREDENTIAL_MANAGER_SET_ORIGIN` has protection level `normal`. `CredentialManagerService` enforces it whenever a create, get, or prepare-get request carries a non-null origin. The browser APK already declares this permission, so no platform signature, privileged installation, framework permission patch, or `pm grant` workaround is part of the experiment.
- `PrepareGetCredentialResponseInternal.hasCredentialResults()` separately requires the normal permission `android.permission.CREDENTIAL_MANAGER_QUERY_CANDIDATE_CREDENTIALS`. The first treatment run reached the provider and reported conditional availability `true`, but the browser process then raised `SecurityException: caller doesn't have the permission to query credential results`. Adding the normal permission to the browser flavor manifest eliminated the crash. No framework permission bypass or privileged installation was needed.
- AOSP keeps enabled providers in `Settings.Secure.CREDENTIAL_SERVICE` and primary providers in `Settings.Secure.CREDENTIAL_SERVICE_PRIMARY`, both as colon-separated flattened component names. The Cuttlefish setup will place the test provider in both settings: enabled is needed for get/prepare-get, and primary makes it the default create target.
- Final Chromium patch: `chromium/chromium-webview-browser-conditional-formatted.patch`, SHA-256 `71cd00194e2d8ddfe5e7b65e124c41ddc66e9e5206ada20a851c950a1066a53d`. It leaves `WebauthnMode.BROWSER` in place, allows GMS-free WebView Credential Manager on API 34+, routes only BROWSER conditional get through `prepareGetCredential`, and initializes the WebView-side generic delegate.
- The unpatched `system_webview_apk` full build completed in 2 h 2 min 12 s (46,167 build steps). Applying and formatting the source change then rebuilt the patched APK incrementally in 46.58 s (11 steps). Both APKs are `com.android.webview` version `154.0.8011.0` / version code `801100007`, compile SDK 37, target SDK 36, min SDK 29, and have the same test signing-certificate SHA-256 `32a2fc74d731105859e5a85df16d95f102d85b22099b8064c5d8915c61dad1e0`.
- Targeted Chromium Robolectric coverage passed at both API 29 and API 36: `AuthenticatorImplTest.testConditionalMediationAvailable_browserCredManWithoutGms` proves the BROWSER-mode availability gate no longer depends on GMS when WebView Credential Manager is enabled, and `Fido2CredentialRequestRobolectricTest.testConditionalGetCredential_webAuthnModeBrowser_goesToCredManPrefetch` proves the conditional request is routed to `startPrefetchRequest` (4/4 executions passed). An existing upstream conditional-CredMan test was also run as a control and passed at both SDK levels (2/2).
- Cuttlefish host package `1.57.0` initially failed on Ubuntu 22.04 because the bundled `virtio-media 0.0.7` code initialized `v4l2_requestbuffers.flags`, while Ubuntu 22.04's Linux 5.15 userspace header exposes only the older reserved field. Replacing direct version-specific field initialization with the common fields plus `..Default::default()` in the cached crate and the two equivalent Cuttlefish call sites made three targeted media binaries and the complete host-package build pass. The exact source diff and both generated Debian packages are preserved; this is a host-build compatibility patch, not a passkey or Android-framework behavior change.
- `cuttlefish-base 1.57.0` and `cuttlefish-user 1.57.0` are installed on the nested-virtualization Spot VM. `/dev/kvm` is present and the build user belongs to `kvm`, `render`, and `cvdnetwork`. Package configuration warns that `vhci-hcd` is unavailable on the GCP kernel; USB/IP passthrough is outside this emulator experiment.
- The final `m dist` succeeded after all image dependencies, including `super.img`, `vbmeta.img`, and `vbmeta_system.img`, were rebuilt together. The device booted with `sys.boot_completed=1`; four consecutive reads of the PermissionController APK produced the same SHA-256 `f4ba799211820c64f1a0698df034b48b4bf1f4385224f5d9969b9bb78141f05b`.
- Nested QEMU required two explicitly scoped boot-support changes unrelated to passkeys: omit unresolved flag-gated Advanced Protection entries that fatally stopped current `system_server`, and allow `AOSPMAN_DISABLE_QEMU_PSTORE=1` to omit QEMU NVDIMM/ramoops arguments that caused a kernel panic. The final QEMU command line and `/proc/bootconfig` contained no pstore/ramoops arguments. `--use_overlay=false` was also necessary because QEMU qcow2 OS overlays produced non-repeatable system-APK reads on this host.
- The unpatched control WebView (`com.android.webview` 154.0.8011.0) logged `AOSPMAN_CONDITIONAL_AVAILABLE false`. The patched APK, installed as a same-signed update over that control, logged `true`, and Credential Manager created a prepare-get session for `TYPE_PUBLIC_KEY_CREDENTIAL` against the test provider.
- Explicit creation for `[redacted-test-user]` showed the AOSP Credential Manager save sheet, launched the provider's `CreatePasskeyActivity`, required device PIN, and returned an RP-verified authenticated page with one registered passkey for the expected RP ID and origin.
- After logout, merely focusing the empty `login-username` field opened the Credential Manager candidate sheet with `[redacted-test-user]`. Selecting it launched `GetPasskeyActivity`; after PIN confirmation, `CredentialManager` logged `onFinalResponseReceived`, and the RP again displayed `AUTHENTICATED` / `ログインできました`. This is the requested WebView passkey autofill/conditional behavior.

## Result and causal assessment

The experiment succeeded. The same Android 17 image, browser package/signature, provider, origin, and Chromium revision produced `false` with the unpatched WebView and a complete create-plus-conditional-login flow with the patched WebView. The smallest causal Chromium change is not switching to `CHROME` or `CHROME_3PP_ENABLED`; the tested app remains `WebauthnMode.BROWSER`. The patch enables the existing WebView Credential Manager prefetch path for BROWSER conditional requests and installs a WebView-side `WebAuthnClientAndroid` so the existing Android Autofill provider can retain and trigger the prepared request on field focus.

An AOSP-only image did need a CredentialProvider implementation to complete an end-to-end cryptographic result because Google Password Manager is absent. The test provider fulfilled that role without weakening provider approval, caller signature, origin, RP ID, or device-security checks. It is test code based on Android's MyVault sample, not a production credential store.

The query-candidate permission incident is an app integration requirement, not evidence for an additional framework patch: both required Credential Manager browser permissions are normal permissions at the pinned framework revision and were granted through manifest declaration.

## Remaining uncertainty and next experiment

- This proves AOSP Credential Manager UI backed by the included test provider. It does not prove Google Password Manager approval or Chrome Password Manager/keyboard-inline branding; those remain external provider-policy and Google-services questions.
- The observed conditional UI is AOSP Credential Manager's candidate bottom sheet triggered by username focus. Whether a product build renders an IME-inline suggestion instead is provider/UI implementation specific and was not required for WebAuthn completion here.
- The final image includes two boot-support workarounds for the pinned Android 17/QEMU/nested-GCP combination. Re-test those independently when upstream fixes the Advanced Protection aconfig resolution and QEMU pstore panic; they do not modify Credential Manager or WebAuthn behavior.
- A production browser should add instrumentation coverage that asserts both Credential Manager permissions are declared, and should handle a missing query-candidate permission defensively rather than allowing the framework `SecurityException` to terminate the process.

## Artifacts and hashes

- `apks/aospman-test-credential-provider-debug.apk`: SHA-256 `a7e4809a1df0aeb79466916796e8abaef523ee720ba11122a3a9336e769eb157`.
- `apks/webview-passkey-browser-browser-query-debug.apk`: final tested APK with both normal Credential Manager permissions, SHA-256 `80febc1d8a4e37f5b92dde70db0d56ae05d91068785f7b52213cbd8f40af06df`. The app logs `AOSPMAN_CONDITIONAL_AVAILABLE true|false` from the actual JavaScript availability promise.
- `apks/webview-passkey-browser-browser-debug.apk`: preliminary APK without the query-candidate permission, SHA-256 `7f5952561d21bef98dfb0b78f9524e29bea145ce3de0900430cd9816eb06cae8`; retained to reproduce the diagnostic `SecurityException` only.
- `apks/webview-passkey-browser-control-debug.apk`: SHA-256 `e6813e3a15ae41f18c5d5f34233b16d067f6ead4799ffe04f45e2e49529eb50f`.
- `test-reports/provider-unit-tests/`: Gradle HTML unit-test report.
- `chromium/control-SystemWebView64.apk`: unpatched control, SHA-256 `38a214fd63ceae5d1b93374ec8ec9b466cdbd16e4ccf63170467b87d272d1dc7`.
- `chromium/patched-SystemWebView64.apk`: patched treatment, SHA-256 `29fbd6f64673b426b654e79e9173f4655bf31b795c710d2aa8a4f14154583dee`.
- `chromium/chromium-webview-browser-conditional-formatted.patch`: exact formatted source diff, SHA-256 `71cd00194e2d8ddfe5e7b65e124c41ddc66e9e5206ada20a851c950a1066a53d`.
- `chromium/build-metadata.txt` and `chromium/SHA256SUMS.remote.txt`: pinned revisions, GN arguments, and remote checksums. `chromium/logs/` contains the full control/treatment build logs and passing/failing test evidence.
- `aosp/cvd-host_package.tar.gz`: final AOSP-built Cuttlefish host package, SHA-256 `a8454192ce43165ff17b27f99163a728ec78350a673a2f12089b5f40700d0451`.
- `aosp/aosp_cf_x86_64_only_phone-img-yusuke-iwaki.zip`: final Android 17 userdebug images, SHA-256 `103ae55f5381cdf45c02120c969ff62eabb0aeaeda0bb47270bf0efd1458e700`.
- `aospman-final-records.tar.gz`: complete remote build metadata, source diffs, logs, screenshots, uiautomator XML, and final device state, SHA-256 `bcba7426943db449ab5dfd260ce55afe1af382e67daae44422c0b10bd52fb9ad`. It is also extracted under `records/`.
- `records/aospman-artifacts/cuttlefish/`: `cuttlefish-base_1.57.0_amd64.deb`, `cuttlefish-user_1.57.0_amd64.deb`, SHA-256 manifest, and the Ubuntu 22.04 V4L2 compatibility patch.
- `records/aospman-artifacts/final/`: exact final AOSP/Cuttlefish source diffs, revision IDs, checksums, final device state, and final logcat.
- `records/aospman-evidence/control/04-browser-launched/`: control screenshot/UI/logcat with conditional availability `false`.
- `records/aospman-evidence/treatment/28-conditional-ui/`: username-focus candidate UI and Credential Manager/provider logcat; `records/aospman-evidence/treatment/34-conditional-login-success/` contains the completed assertion and authenticated-page evidence.
- `evidence/control-conditional-unavailable.png`, `evidence/treatment-conditional-ui.png`, `evidence/treatment-create-success.png`, and `evidence/treatment-conditional-login-success.png`: convenient rendered screenshots of the control, candidate UI, completed creation, and completed conditional login states.

## Tests and warnings

- 2026-08-19 JST preflight: no existing instances, disks, reserved addresses, snapshots, or custom images.
- Preferred `c3d-highcpu-90` is unavailable (`C3_CPUS` limit 24). `n2-highcpu-96` also exceeds the project-wide `CPUS_ALL_REGIONS` limit 32. No quota increase was requested; the constrained build profile is `n2-highcpu-32` (32 vCPU, 32 GiB).
- Regional `SSD_TOTAL_GB` limit is 500, so the two large source trees are built sequentially on separate 500 GB auto-deleting `pd-balanced` disks instead of sharing one disk.
- Initial VM creation attempts failed before resource creation due to a retired image-family alias, project-wide CPU quota, and SSD quota. The management script was updated to use `ubuntu-2204-lts` and preflight the newly observed quotas.
- First bootstrap exposed a stale/missing base APT index in the current Ubuntu image. Re-running update with `Acquire::http::No-Cache=true` restored the base index; bootstrap then completed.
- The provider `:app:assembleDebug` and `:app:testDebugUnitTest` tasks completed successfully. Warnings inherited from the sample include missing Room schema export configuration, deprecated API use, and an unstripped AndroidX graphics native library. The app is a test-only provider with sample storage and must not be treated as production credential storage.
- The repository-local `record-android-passkey-investigation` skill passed the skill-creator `quick_validate.py` check. Its `new_record.py` smoke test created a record and then correctly refused to overwrite the same path; its `agents/openai.yaml` was regenerated with the canonical metadata generator.
- Chromium build dependencies and hooks completed on Ubuntu 22.04. The first non-interactive hook invocation missed `depot_tools` in PATH; it was rerun with `/home/yusuke-iwaki/depot_tools` explicitly prepended.
- The first version of the new prefetch unit-test assertion mixed one raw first argument with six Mockito matchers under the Chromium test class's matcher resolution and failed before checking product behavior. The assertion was aligned with the existing upstream routing-test pattern (all seven arguments matched), after which both new tests passed on both configured SDKs. The initial failure log is retained alongside the final passing log rather than discarded.
- The first AOSP `repo sync -j8` stopped during concurrent work-tree initialization: `external/openscreen` reported that `/work/aosp/kernel/configs` did not yet exist. A lower-concurrency retry then encountered a transient `RESOURCE_EXHAUSTED` response while fetching DeviceDiagnostics; the final retry completed and the manifest was captured. All sync logs are retained.
- The first `m -j16 dist` attempt was killed by the kernel OOM killer during Soong analysis on the 32 GiB host. A 32 GiB swap file allowed Soong analysis to finish with `-j12`. Later `-j24` and `-j16` Ninja resumptions were stopped deliberately after Java/Rust concurrency drove load and swap sharply upward; the durable systemd-managed `-j12` resumption is the build used for the final artifacts.
- Replacing the AOSP preinstalled WebView through `adb install` first failed with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, as expected, because the AOSP and Chromium build keys differ. On this disposable userdebug image, the exact resolved path `/product/app/webview/webview.apk` was replaced after `disable-verity`/`remount`. The patched treatment then installed cleanly as a same-signed update over the control.
- The final browser Gradle tasks `:app:assembleBrowserDebug` and `:app:testBrowserDebugUnitTest` passed after adding `CREDENTIAL_MANAGER_QUERY_CANDIDATE_CREDENTIALS`; `aapt dump permissions` confirmed both Credential Manager permissions in the APK.

## GCP resources and cleanup

- Project: `aospman` (explicit on every gcloud operation).
- Removed: `aospman-chromium-webview-20260819`. Chromium artifacts and complete logs were copied locally, SHA-256 values were rechecked, the VM and auto-delete disk were deleted, and the subsequent resource audit was clean.
- Removed: `aospman-cuttlefish-20260819`, `asia-northeast1-b`, `n2-highcpu-32`, Spot, termination action DELETE, 8-hour maximum, 500 GB auto-deleting `pd-balanced`, no service account/scopes, labels `managed-by=aospman`, `workload=android-build`, `lifecycle=ephemeral`, nested virtualization enabled. The final host/image packages and complete records archive were copied locally and their SHA-256 values rechecked before deletion.
- Final audit after deleting both managed VMs: no instances, disks, reserved addresses, snapshots, or custom images remained in project `aospman`.
