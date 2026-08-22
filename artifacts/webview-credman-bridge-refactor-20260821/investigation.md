# Architecture-preserving WebView CredMan conditional bridge refactor

- Date: 2026-08-21 to 2026-08-22
- Status: complete
- Hypothesis: On a pinned current Chromium revision, extracting CredMan conditional callbacks from the Chrome-only WebauthnBrowserBridge into a common coordinator while keeping WebauthnMode.BROWSER and API 34+ Credential Manager routing will preserve ordinary WebAuthn and Chrome-only bridge semantics, pass targeted regression tests, and reproduce passkey create plus focused-field conditional get on the same authorized-provider Cuttlefish control/treatment setup.

## Question and scope

Can Chromium WebView support ordinary passkey create/get and focused-field conditional passkey sign-in on Android 14+ without making the README-declared Chrome-only `WebauthnBrowserBridge` available to `WebauthnMode.BROWSER`? The treatment will extract the Credential Manager conditional-request coordination needed by both embedders, keep Chrome-only credential enumeration/custom UI behind the existing browser bridge, and validate control/treatment plus regression behavior.

Ordinary WebAuthn, browser-origin delegation, provider trust, conditional mediation, and Chrome Password Manager UI remain separate outcomes. Google Password Manager approval is out of scope; the same locally authorized test provider from the prior experiment is used without weakening caller, signature, origin, RP-ID, or device-security checks.

## Configuration

### Local and upstream revisions

- Local repository: `git@github.com:YusukeIwaki/aospman.git` at starting commit `e1ed2328462b3a93a0ccb64c00c551b4c8c74900`; the pre-existing follow-up edit to `artifacts/webview-conditional-cuttlefish-20260819/investigation.md` is preserved.
- Chromium source: `https://chromium.googlesource.com/chromium/src.git` pinned at task-start `main` commit `98596990901c11e89a24f6217f1b66513b065026` (2026-08-21T13:51:16-07:00, Cr-Commit-Position `refs/heads/main@{#1683865}`).
- Prior proven treatment source, retained only as behavioral reference: Chromium `e807462122f5935c440b9bd4a9721e1cb8ac6e4e`, version `154.0.8011.0`, patch SHA-256 `71cd00194e2d8ddfe5e7b65e124c41ddc66e9e5206ada20a851c950a1066a53d`.
- AOSP image source remains the pinned prior Android 17 manifest (`android17-release`, manifest checkout `ad156f32caaa06dae91c02d443f6a8fe210eaa54`; exact revision map preserved under the prior experiment records). No AOSP source change is planned.

### Device, apps, and provider

- Tested device: the preserved x86_64 AOSP Cuttlefish `userdebug`, Android 17/API 37, build ID `CP2A.260605.016`, fingerprint `generic/aosp_cf_x86_64_only_phone/vsoc_x86_64_only:17/CP2A.260605.016/eng.yusuke:userdebug/test-keys`.
- Control: unmodified `system_webview_64_apk` built from Chromium `98596990`; treatment: same checkout/GN args/signing identity with only the architecture-preserving CredMan conditional refactor applied.
- Browser: `com.example.webviewpasskeybrowser.browser`, AndroidX WebKit browser mode, manifest permissions `CREDENTIAL_MANAGER_SET_ORIGIN` and `CREDENTIAL_MANAGER_QUERY_CANDIDATE_CREDENTIALS`; preserved APK SHA-256 `80febc1d8a4e37f5b92dde70db0d56ae05d91068785f7b52213cbd8f40af06df`, signing certificate SHA-256 `d6b890eca6f4708aff24be19176c56afee38d8d4d5612a9964f5f581ccc2b4b1`.
- Provider: `com.example.aospman.passkeyprovider`, locally authorizing only the browser package/certificate above; preserved APK SHA-256 `a7e4809a1df0aeb79466916796e8abaef523ee720ba11122a3a9336e769eb157`.

### Relying party

- Origin: `https://passkey-test-lab-production.up.railway.app/`
- RP ID: `passkey-test-lab-production.up.railway.app`

## Experiment design

| Case | Control or treatment | Expected falsifier | Result |
| --- | --- | --- | --- |
| Source architecture | Treatment keeps `WebauthnBrowserBridge` Chrome-only and introduces a common CredMan conditional coordinator | BROWSER still returns/constructs the Chrome browser bridge or README invariants must be weakened | Passed. BROWSER receives only `WebauthnCredManBridge`; Chrome-only UI/enumeration remains in `WebauthnBrowserBridge`. No `android_webview/browser` change. |
| Targeted tests | New BROWSER conditional tests plus existing Chrome/CredMan tests | Compile failure or any targeted regression | Passed: 178/178 Robolectric executions across API 29 and 36. Native factory/delegate test objects compiled. |
| Complete provider build | Control and treatment `system_webview_64_apk`, same revision/GN args | Java/native/resources fail to package or identities drift | Passed. Both APKs are `com.android.webview` 154.0.8016.0, versionCode 801600007, x86_64, with the same signing certificate. |
| Control conditional get | Unmodified current WebView, same device/app/provider/RP | Reports conditional mediation available or opens provider UI on focus | Passed baseline: page badge showed `Autofill 未対応`; log recorded `AOSPMAN_CONDITIONAL_AVAILABLE false`; no provider UI appeared. |
| Control ordinary create/get | Unmodified current WebView on GMS-free AOSP | Unexpectedly reaches CredMan despite the known GMS preflight blocker | Retained expected baseline behavior: no authorized-provider dispatch. This is diagnostic because the unmodified current code rejects before WebView CredMan on GMS-free AOSP. |
| Treatment ordinary create | Refactored WebView | Request no longer reaches the authorized provider or RP registration verification fails | Passed for a fresh test user; save sheet, provider, device PIN, final credential, RP verification, and authenticated account page all completed. |
| Treatment modal get | Refactored WebView, username plus sign-in button | Provider/RP cannot complete an ordinary non-conditional assertion | Passed; `executeGetCredential`, provider result, `onFinalResponseReceived`, `/account`, and `AUTHENTICATED` were recorded. |
| Treatment conditional get | Refactored WebView | Availability remains false, load shows premature UI, focus does not open a candidate, or assertion fails | Passed; availability was true without premature sheet, username focus opened the saved-passkey candidate, and the assertion completed to the authenticated account page. |
| Lifecycle/regression | Conditional and ordinary paths plus selected upstream tests and Chrome APK link | Stale UI, crash, Chrome-path test/build failure, or ordinary WebAuthn regression | Passed within tested scope. A second fresh-page modal get completed after the conditional get. `chrome_public_apk` linked successfully. |

## Reproduction

```text
spot-vm.sh audit
spot-vm.sh preflight preferred
spot-vm.sh preflight fallback
spot-vm.sh preflight constrained
AOSPMAN_ENABLE_NESTED_VIRT=1 spot-vm.sh create constrained \
  aospman-webview-refactor-20260821 8 500
spot-vm.sh bootstrap aospman-webview-refactor-20260821

fetch --nohooks --no-history chromium
cd /work/chromium/src
git fetch origin 98596990901c11e89a24f6217f1b66513b065026 --depth=1
git checkout --detach FETCH_HEAD
gclient sync --nohooks --no-history
./build/install-build-deps.sh --no-prompt --no-chromeos-fonts
gclient runhooks --force

gn gen out/webview-x64 --args='target_os="android" target_cpu="x64" \
  is_debug=false is_component_build=false symbol_level=0 \
  blink_symbol_level=0 v8_symbol_level=0 use_remoteexec=false \
  treat_warnings_as_errors=false'
autoninja -C out/webview-x64 system_webview_64_apk
```

## Observations and evidence

- Task-start source audit confirms current README still declares `WebauthnBrowserBridge` exclusive to `CHROME`/`CHROME_3PP`, while BROWSER+FULL routes ordinary get/create through Credential Manager.
- No adb device was connected at task start. The preserved Cuttlefish host/image packages and browser/provider APK hashes were rechecked and match the prior clean experiment.
- Immediately before the planned device run, the pinned RP origin returned HTTP 200 and the expected `パスキー動作確認 | Passkey Test Lab` page title.
- The treatment design moves `onCredManConditionalRequestPending`, `onCredManUiClosed`, password delivery, and CredMan cleanup into a stateless common `WebauthnCredManBridge`. `WebauthnBrowserBridge.getBridge()` remains unchanged and returns null outside Chrome modes; Chrome credential enumeration/custom UI stays on that bridge.
- The corresponding non-virtual CredMan forwarding methods are also removed from `WebAuthnClientAndroid`; after extraction, that client and `WebauthnBrowserBridge` retain only the Chrome custom-UI contract plus request-disallow signaling.
- WebView does not install or subclass Chrome's `WebAuthnClientAndroid`. The common bridge explicitly enables `WebAuthnCredManDelegateFactory` for the request's `WebContents` only when a conditional CredMan request becomes pending, then talks directly to the resulting per-frame delegate. No `android_webview/browser` source change is required.
- Conditional get is enabled only for `WebauthnMode.BROWSER` with WebView CredMan support. Conditional create remains Chrome-only and is not newly advertised.
- Review of the first draft found that a broad GMS-free make-credential exception would also let BROWSER conditional create reach the GMS Identity Credentials helper. The treatment now limits that exception to non-conditional create and adds a negative test requiring GMS-free BROWSER conditional create to remain `NOT_IMPLEMENTED`.
- A second source review confirmed the ownership boundary after extraction: BROWSER still receives `null` from `Fido2CredentialRequest.getBridge()`, while Chrome credential enumeration, hybrid callbacks, custom-picker initialization, generic browser cleanup, and request-disallow checks remain on `WebauthnBrowserBridge`. Only CredMan pending/closed/password/conditional-cleanup callbacks use the common stateless bridge.
- The factory keeps its existing Chrome behavior (`WebAuthnClientAndroid::HasClient()`), while adding an explicit per-`WebContents` opt-in used by the common CredMan bridge after a real request callback. This removes the draft's empty WebView overrides of Chrome UI methods, avoids globally broadening delegates to unrelated WebViews, and replaces the implicit client signal with the capability actually required.
- `WebAuthnCredManDelegateFactoryTest.GetDelegateWhenEnabledWithoutClient` covers the new explicit opt-in, while the existing `GetNoDelegateWithoutClient` test remains unchanged to prove other embedders do not gain delegates implicitly.
- The first control `gn gen` stopped before compilation because the initial non-forced hook run had not generated `build/util/LASTCHANGE.committime`. `gclient runhooks --force` completed all hooks and generated both `LASTCHANGE` files; the control build was restarted with unchanged source and GN args.
- The first build command used the historical compatibility target `system_webview_apk`. At this revision that target successfully builds/copies only the `bin/system_webview_apk` operations wrapper, so the subsequent stale `apks/SystemWebView.apk` copy failed. Source compilation results were retained and the actual APK group `system_webview_64_apk` was resumed incrementally; its declared output is `apks/SystemWebView64.apk`.
- The first `system_webview_64_apk` attempt inherited the default 32-way local parallelism and exhausted the 31 GiB VM RAM (9 MiB available, no swap), leaving all clang processes blocked in memory reclaim. After interrupt signals could not be scheduled for over three minutes, the VM was reset once. The auto-deleting boot disk and all completed objects/logs were preserved; after reboot memory returned to 30 GiB available, `build.ninja` remained present, and `git status --short` remained empty. The target is resumed with bounded parallelism.
- A transient 8 GiB swap file was enabled on the existing auto-deleting boot disk as a spike guard (not added to `fstab` and requiring no additional GCP resource). The safe `-j16` resume used 15–22 GiB RAM; after confirming stability, the siso parent was stopped cleanly and parallelism was raised first to `-j20`, then finally capped at `-j24` when the live core workload remained within RAM. Swap remained unused at the `-j24` start. All subsequent Chromium targets use bounded parallelism no higher than 24.
- The same-device control cannot serve as a successful ordinary-WebAuthn baseline because this AOSP image has no GMS and unmodified `AuthenticatorImpl` rejects make/get before reaching WebView's API-34 CredMan route. That rejection will be recorded as the known control behavior; ordinary-path non-regression is assessed through the treatment's complete create/modal-get device flows plus existing upstream Chrome/CredMan test classes.
- The control `system_webview_64_apk` and treatment incremental build both completed. Control SHA-256 is `915038de8dbeba31cd6dee5b609a00118d387059df782f155c626a2353a42f9c`; treatment SHA-256 is `a10edece2e3fb11493001cb22f7e68dda9d78c20ed913936d7fad0a98661102a`. Both report package `com.android.webview`, versionName `154.0.8016.0`, versionCode `801600007`, min/target 29/36, ABI x86_64, and signing-certificate SHA-256 `32a2fc74d731105859e5a85df16d95f102d85b22099b8064c5d8915c61dad1e0`.
- The full treatment `chrome_public_apk` completed 10,071 steps and final `libchrome.so` link/APK packaging in 22m57s. Its package is `org.chromium.chrome`, versionName `154.0.8016.0`, versionCode `801600008`, and APK SHA-256 `e9528da0c2753821bb6b0e92b7e4e06227990d79f3a71e3fd9b338559e9d5414`.
- The aggregate Java dependency build completed 6,323 steps. The three selected classes (`AuthenticatorImplTest`, `Fido2CredentialRequestRobolectricTest`, and `CredManHelperRobolectricTest`) then passed 178/178 executions: 89 on API 29 and 89 on API 36. This includes the new BROWSER no-GMS ordinary/conditional routing tests, conditional-create negative case, APP/pre-34 negative cases, and existing Chrome/CredMan coverage.
- `components/webauthn/android:unit_tests` completed its 1,854-step source-set build; both `webauthn_cred_man_delegate_unittest.o` and the modified `webauthn_cred_man_delegate_factory_unittest.o` compiled. This is native test compilation, not a claimed host gtest execution.
- The control APK was placed at the resolved userdebug product path `/product/app/webview/webview.apk` after disable-verity/remount and reboot. A normal same-signed treatment update was attempted but failed with `INSTALL_FAILED_INSUFFICIENT_STORAGE`: the Cuttlefish overlay occupied 6.5 GiB under `/data/gsi/remount`, leaving insufficient package-expansion space. The treatment was therefore written to the exact same product path and rebooted, keeping the only comparison variable the WebView APK bytes.
- Control device evidence showed `Autofill 未対応` and logged `AOSPMAN_CONDITIONAL_AVAILABLE false`. Treatment showed `Autofill 対応` and logged `true`; Credential Manager constructed a prepare-get request for `TYPE_PUBLIC_KEY_CREDENTIAL`. One cold-start prepare response timed out while the provider process was starting; the subsequent create, conditional get, and modal get provider sessions all returned valid responses without retrying the APK or changing configuration.
- Ordinary create for a fresh test user reached the AOSP Credential Manager save sheet branded `Aospman Test Passkeys`, launched the provider's `CreatePasskeyActivity`, required the configured device PIN, and produced a final credential accepted by the RP. The authenticated page recorded one registered passkey, the expected RP ID, and expected HTTPS origin.
- After logout, merely focusing the empty username field invoked `executeGetCredential` and displayed the saved-passkey candidate. Selection, provider `GetPasskeyActivity`, PIN, `onFinalResponseReceived`, and RP verification all completed. A later username-plus-button modal get repeated the assertion path and also reached `AUTHENTICATED`.
- No Google Password Manager approval, Chrome Password Manager UI, signature/origin/RP-ID bypass, provider-trust bypass, or device-security bypass was introduced or claimed. The device result is for AOSP Credential Manager with the explicitly authorized test provider.

## Result and causal assessment

The hypothesis is confirmed for the tested revision and configuration. The architecture-preserving refactor supports ordinary passkey create/get and conditional/autofill get in a third-party BROWSER-mode WebView without exposing the README-declared Chrome-only `WebauthnBrowserBridge` to WebView. Control and treatment used the same Chromium revision, GN args, WebView identity, device/image, browser APK/signature, provider APK/configuration, RP origin, and device PIN; only the WebView APK bytes differed.

The causal change is the extraction of the four Credential Manager lifecycle callbacks into common `WebauthnCredManBridge`, plus explicit per-`WebContents` delegate enablement and BROWSER/API-34/full-CredMan routing. Chrome's custom picker, enumeration, hybrid UI, request-disallow, and generic browser cleanup remain behind `WebauthnBrowserBridge`/`WebAuthnClientAndroid`. Conditional create remains Chrome-only. The 178/178 Java result, native test-object compilation, complete WebView packages, full Chrome APK link, and three successful device flows provide no observed regression in this scope.

## Remaining uncertainty and next experiment

- The authorized AOSP sample provider proves Chromium/WebView/Credential Manager plumbing and complete cryptographic RP results; it does not prove Google Password Manager's privileged-browser approval or branded Chrome Password Manager/keyboard-inline UI.
- The native Android unit-test source set compiled, but its gtests were not executed as a host suite. The device test exercised the modified native delegate factory and JNI bridge end to end.
- `ChromePublic.apk` fully built and linked, but Chrome passkey UI was not device-tested because the test provider intentionally authorizes only the third-party browser package/signature. Expanding provider authorization merely to test Chrome would change the trust matrix and was not done.
- A production change should receive Chromium owner review for the new explicit delegate-factory opt-in and decide whether BROWSER CredMan enablement needs a feature flag or Finch control beyond the existing WebView CredMan support gate.

## Artifacts and hashes

- Prior Cuttlefish host package: SHA-256 `a8454192ce43165ff17b27f99163a728ec78350a673a2f12089b5f40700d0451`.
- Prior Cuttlefish image package: SHA-256 `103ae55f5381cdf45c02120c969ff62eabb0aeaeda0bb47270bf0efd1458e700`.
- Original formatted build-checkout patch SHA-256: `0ac7d74793f35490f1fd3483d442f2154111140a7e39c0180be5f8ab72c738e4` (18 files, 507 insertions, 329 deletions). The VM copy was lost at automatic deletion during final transfer.
- Re-exported patch from the locally preserved source snapshot, re-formatted using pinned Chromium clang-format 23 (`a1fb1726...`), GN 2527 (`58933a7c...`), and the pinned google-java-format CIPD plus Chromium override: `chromium/chromium-webview-credman-bridge-refactor-recreated.patch`, SHA-256 `d6c264ac07a3d80d2d2dba065ba36cc06bad64cb4c1d3eda714aeb9cad815907`. The identical review copy is committed as `../../patches/chromium-webview-browser-conditional.patch`. It has the same 18-file/507/329 stat, passes `git diff --check`, and `git apply --check` succeeds against a pristine sparse checkout at the pinned commit.
- Control and treatment WebView APKs are retained locally under `chromium/`; hashes are listed above. They are intentionally omitted from Git because each APK is approximately 318 MiB.
- Device screenshots, UI XML, activity state, and logcat are under `evidence/control/` and `evidence/treatment/`. The key treatment states are `04-scrolled`, `10-create-sheet`, `14-create-result`, `19-conditional-sheet`, `23-conditional-login-success`, `29-modal-sheet`, and `32-modal-login-result`.
- Derived durable build/test summaries are under `chromium/logs/build-summary.md` and `chromium/test-results/summary.json`. Raw remote build logs and the Chrome APK were not copied before the maximum-lifetime VM deletion.

## Tests and warnings

- Chromium dependency installation and hooks completed. The first bootstrap attempt encountered a transient SSH `connection refused` while the fresh VM was still starting; retry succeeded without changing the VM.
- Control/treatment `system_webview_64_apk`, treatment `chrome_public_apk`, aggregate Java build, selected Robolectric run, and native test-source build completed as detailed above.
- Preserved Cuttlefish host/image, browser APK, provider APK, and Cuttlefish Debian packages were copied to the VM and rehashed. The host/image/browser/provider hashes exactly match the values recorded above; Debian package SHA-256 values are `a9cac932edaedae6351df7a1ff4a07ca19c4dc674efc756b39e69563037dde53` and `0b8999a2c149da36c70ff743d8dca4ed4f7283cef7119d19edfbe60ec0f14f93`.
- Cuttlefish `base` and `user` packages version `1.57.0` installed successfully, and the VM user was added to `kvm`, `render`, and `cvdnetwork`. Package setup warned that optional host module `vhci-hcd` is absent from the GCP kernel; it did not block the nested-QEMU device run.
- The rehashed host and image archives extracted successfully into `/work/cuttlefish-runtime` (3.6 GB) and were used for the control/treatment device run after Chromium builds completed.

## GCP resources and cleanup

- Task-start audit was clean: no instances, disks, reserved addresses, snapshots, or custom images in project `aospman`.
- Live preflight: preferred `c3d-highcpu-90` failed the 24-vCPU C3 quota; fallback `n2-highcpu-96` failed the 32-vCPU all-regions quota; constrained `n2-highcpu-32` passed. No quota increase was requested.
- Created `aospman-webview-refactor-20260821` in `asia-northeast1-b`: Spot `n2-highcpu-32`, termination action DELETE, maximum run duration, 500 GB auto-deleting `pd-balanced` (live regional SSD quota limit), ephemeral external IP, no service account/scopes, required management labels, nested virtualization enabled for Cuttlefish.
- The maximum run-duration policy deleted the VM and auto-delete disk during final artifact transfer. This removed the raw remote build logs and uncopied Chrome APK, but the central control/treatment WebView APKs and all device evidence were already local. Post-deletion resource listing found no matching instance or disk. Final `spot-vm.sh audit` is recorded below.
- Final `spot-vm.sh audit` exited 0 and listed no instances, disks, reserved addresses, snapshots, or custom images in project `aospman`. The durable output is `gcp-final-audit.txt`.
