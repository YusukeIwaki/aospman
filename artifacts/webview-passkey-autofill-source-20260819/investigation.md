# Android WebView passkey autofill source investigation

- Date: 2026-08-19 (Asia/Tokyo)
- Status: complete (source investigation and control reproduction; no Chromium patch/build was performed)
- Hypothesis: Conditional mediation is rejected in Chromium's WebView `BROWSER` mode before Credential Manager is called. Android 14+ already supplies the prefetch/pending-handle primitive, and Chromium's common Android Autofill provider already supplies a field-focus trigger. A small but multi-file Chromium/WebView-provider patch can connect those pieces for an OS Credential Manager sheet. Google Password Manager privileged-browser approval remains an independent prerequisite.
- Result: supported. App-only/AndroidX changes are insufficient, but an API 34+ WebView-provider prototype appears feasible without changing the Android Credential Manager framework.

## Question and scope

Determine why `navigator.credentials.get({mediation: "conditional"})` / passkey Autofill is unavailable in the current WebView-backed test browser, and identify the smallest reviewable Android framework or Chromium WebView source changes that could make it work against:

- origin `https://passkey-test-lab-production.up.railway.app`;
- RP ID `passkey-test-lab-production.up.railway.app`;
- app package `com.example.webviewpasskeybrowser.browser` in AndroidX WebKit browser mode.

The investigation keeps these concerns separate:

1. ordinary WebAuthn `create()` / modal `get()` routing;
2. WebView `BROWSER` mode and asserted web origin;
3. conditional mediation availability and deferred field-focus UI;
4. Google Password Manager's privileged-browser package/signing allowlist;
5. Chrome Password Manager / keyboard accessory / touch-to-fill integration.

No provider trust, origin, signature, device-security, or WebView-provider validation check was changed or bypassed.

## Configuration

### Local and upstream revisions

- Local repository: `git@github.com:YusukeIwaki/aospman.git`
- Local starting revision: `a4f7863ae52c91e31dd525be9a843cb055a74d7d`
- Chromium installed-WebView tag revision: `49ec12cc413ffec766028509968b31d7d65fa0b7` (Chromium 133.0.6943.137, 2025-02-24)
- Chromium current-main revision pinned for the proposed patch: `ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b` (2026-08-19)
- AOSP `platform/frameworks/base`: `1cdfff555f4a21f71ccc978290e2e212e2f8b168`
- AndroidX WebKit binary used by the app: `androidx.webkit:webkit:1.14.0`
  - AAR SHA-256: `265604786ea1c9679e3f860f7f13072375c141f46db9092ed8ef5ecd599a516d`
  - The AAR exposes `WEB_AUTHENTICATION_SUPPORT_FOR_APP`, `WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER`, `set/getWebAuthenticationSupport`, and the `WEB_AUTHENTICATION` feature. No conditional-mediation host API is present.

Pinned source entry points:

- Chromium current `components/webauthn/android/README.md`: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/README.md>
- Chromium current `AuthenticatorImpl.java`: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/java/src/org/chromium/components/webauthn/AuthenticatorImpl.java>
- Chromium current `Fido2CredentialRequest.java`: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/java/src/org/chromium/components/webauthn/Fido2CredentialRequest.java>
- Chromium current `CredManHelper.java`: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/java/src/org/chromium/components/webauthn/cred_man/CredManHelper.java>
- Chromium current `android_autofill_provider.cc`: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/android_autofill/browser/android_autofill_provider.cc>
- AOSP `CredentialManager.java`: <https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/credentials/CredentialManager.java>

### Device, apps, and provider

- AVD: `medium_phone`, serial `emulator-5554`
- Android: 16 / API 36 / `arm64-v8a`
- Build fingerprint: `google/sdk_gphone64_arm64/emu64a:16/BE2A.250530.026.D1/13818094:user/release-keys`
- Build type: `user`, not `userdebug`
- Android System WebView: `com.google.android.webview` 133.0.6943.137 (`versionCode=694313732`)
- Test browser: `com.example.webviewpasskeybrowser.browser`, version `1.0-browser`
- AndroidX WebKit configuration: `WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER` (`BROWSER=2`)
- Granted browser-origin permission: `android.permission.CREDENTIAL_MANAGER_SET_ORIGIN`
- Test-browser debug-certificate SHA-256: `D6:B8:90:EC:A6:F4:70:8A:FF:24:BE:19:17:6C:56:AF:EE:38:D8:D4:D5:61:2A:99:64:F5:F5:81:CC:C2:B4:B1`
- Credential provider: Google Password Manager through `com.google.android.gms/.auth.api.credentials.credman.service.PasswordAndPasskeyService`

The `user` image accepts only configured/signed WebView providers. A locally signed patched `system_webview_apk` should be tested on an AOSP `userdebug` image. At the pinned AOSP revision, `WebViewUpdateServiceImpl2.providerHasValidSignature()` skips signature checking on debuggable builds, while `config_webview_packages.xml` names `com.android.webview` as the default provider.

### Relying party

- Origin: `https://passkey-test-lab-production.up.railway.app`
- RP ID: `passkey-test-lab-production.up.railway.app`
- Site login field is intended for conditional UI and the page awaits `PublicKeyCredential.isConditionalMediationAvailable()` before starting its Autofill flow.
- Chrome previously completed create/get/conditional flows on this AVD. See `artifacts/chrome-passkey-api36-20260819/investigation.md`.
- Ordinary WebView browser-mode requests reach Credential Manager but Google Password Manager rejects this custom package/certificate as an unapproved privileged browser. See `artifacts/webview-passkey-api36-20260819/investigation.md`.

## Experiment design

| Case | Control or treatment | Expected falsifier | Result |
| --- | --- | --- | --- |
| Stock WebView 133, browser mode | Control | Conditional availability returns true after unlock | Falsified: `Autofill 未対応` remains visible |
| Installed-tag source gate | Source control | WebView `BROWSER` is accepted by `couldSupportConditionalMediation()` | Falsified: the code requires `isChrome()` |
| Actual conditional request | Source control | A request can bypass the availability result and reach CredMan | Falsified: non-Chrome conditional returns `NOT_IMPLEMENTED` |
| Android framework | Source control | Framework rejects a WebView-conditional request type | Falsified: framework exposes generic `prepareGetCredential()` / pending handle and contains no WebView-conditional gate |
| Common Android Autofill | Treatment feasibility | No field-focus trigger exists outside Chrome | Falsified: `AndroidAutofillProvider` recognizes `autocomplete=webauthn` and can trigger `WebAuthnCredManDelegate` |
| End-to-end GPM assertion | Future treatment | Patched WebView alone is sufficient | Not yet testable: GPM approval of the package/signature is independently required |

## Reproduction

Control evidence after manual device unlock:

```text
adb -s emulator-5554 shell am start \
  -n com.example.webviewpasskeybrowser.browser/com.example.webviewpasskeybrowser.MainActivity

# Observe the page badges and WebView hierarchy.
# Result: "WebAuthn 対応" and "Autofill 未対応".
```

Environment confirmation:

```text
adb -s emulator-5554 shell getprop ro.build.version.sdk       # 36
adb -s emulator-5554 shell getprop ro.build.type              # user
adb -s emulator-5554 shell getprop ro.product.cpu.abi         # arm64-v8a
adb -s emulator-5554 shell dumpsys webviewupdate
# Current provider: com.google.android.webview 133.0.6943.137
```

Evidence paths:

- `device-control/screen.png`
- `device-control/ui.xml`

## Observations and evidence

### 1. Availability is deliberately false for WebView

Installed WebView revision `49ec12...`, `AuthenticatorImpl.couldSupportConditionalMediation()` at lines 229-232 requires all of:

- GMS WebAuthn support;
- `isChrome(mWebContents)`;
- Android P or later.

`isConditionalMediationAvailable()` at lines 340-352 immediately returns `false` when that predicate fails. Since AndroidX browser support sets WebView mode to `BROWSER`, not `CHROME`, this exactly explains the page's `Autofill 未対応` result.

The current Chromium revision still has the same mode block: lines 339-341 require `isChrome()`, and lines 482-495 return `false` otherwise. The obsolete Android-P check was removed, but WebView was not enabled.

Installed source: <https://chromium.googlesource.com/chromium/src/+/49ec12cc413ffec766028509968b31d7d65fa0b7/components/webauthn/android/java/src/org/chromium/components/webauthn/AuthenticatorImpl.java#229>

Current source: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/java/src/org/chromium/components/webauthn/AuthenticatorImpl.java#339>

### 2. Bypassing the availability check still returns `NOT_IMPLEMENTED`

Installed `Fido2CredentialRequest.java` lines 477-480 rejects `options.isConditional` whenever the embedder is not Chrome. Current Chromium lines 705-711 performs the same rejection for `Mediation.CONDITIONAL`.

Therefore changing only `couldSupportConditionalMediation()` would produce a false-positive capability report; the real `get()` would still fail before Credential Manager.

Installed source: <https://chromium.googlesource.com/chromium/src/+/49ec12cc413ffec766028509968b31d7d65fa0b7/components/webauthn/android/java/src/org/chromium/components/webauthn/Fido2CredentialRequest.java#477>

Current source: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/java/src/org/chromium/components/webauthn/Fido2CredentialRequest.java#705>

### 3. The correct conditional route is prefetch, not immediate modal get

For ordinary non-Chrome WebView requests, current `Fido2CredentialRequest` calls `CredManHelper.startGetRequest()` directly (lines 730-736). Chrome's Android 14+ conditional route instead calls `startPrefetchRequest()` (lines 748-762).

`CredManHelper.startPrefetchRequest()`:

1. calls Android `CredentialManager.prepareGetCredential()` (lines 409-432);
2. records whether passkey/authentication candidates exist;
3. stores a callback through `onCredManConditionalRequestPending()` (lines 381-395);
4. calls the full `startGetRequest()` only after Autofill field focus triggers that callback.

Simply removing `NOT_IMPLEMENTED` and falling into the ordinary WebView branch would open a modal picker during page load, not implement conditional mediation semantics.

Source: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/java/src/org/chromium/components/webauthn/cred_man/CredManHelper.java#248>

### 4. The bridge is Chrome-only even though the Android 14 delegate path is common

`Fido2CredentialRequest.getBridge()` returns null unless `isChrome()` at current lines 1897-1904 (installed lines 1388-1396). The Chromium architecture README explicitly says `WebauthnBrowserBridge` is designed for Chrome and is not used by Android WebView.

The Android 14 conditional callbacks themselves do not require Chrome Password Manager UI:

- `WebauthnBrowserBridge::OnCredManConditionalRequestPending()` forwards to `WebAuthnClientAndroid`;
- the non-virtual base implementation stores the full-request callback in the common `WebAuthnCredManDelegate`;
- `WebAuthnCredManDelegate::TriggerCredManUi()` invokes it later.

Chrome registers `ChromeWebAuthnClientAndroid` in `BrowserProcessImpl`; Android WebView registers no corresponding client. Pre-Android-14 FIDO credential enumeration additionally needs Chrome's real `OnWebAuthnRequestPending()` candidate UI, so a no-op client is not sufficient there.

Bridge source: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/webauthn_browser_bridge.cc#199>

Delegate source: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/webauthn/android/webauthn_cred_man_delegate.cc#34>

Chrome registration: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/chrome/browser/browser_process_impl.cc#518>

### 5. WebView already creates the common Android Autofill provider

Current `AwContents.java` creates `AutofillProvider` and calls native `initializeAndroidAutofill()` unless WebView safe mode disables Android Autofill. `AwContents::InitializeAndroidAutofill()` creates `AndroidAutofillClient` for the WebContents.

`AndroidAutofillProvider` at current revision:

- recognizes a parsed `autocomplete` token with `webauthn` (lines 118-120);
- on field focus checks whether `WebAuthnCredManDelegate` has finished preparing candidates (lines 596-625 and 780-793);
- calls `delegate->TriggerCredManUi()` (lines 796-809).

The installed M133 revision has one additional deliberate block: `AllowCredManOnField()` requires `kAutofillVirtualViewStructureAndroid`, whose feature default is disabled, with a comment warning against accidental WebView launch. Current Chromium removed this gate. Thus:

- when patching M133, remove/replace that feature gate as part of the treatment;
- when patching current main, no Android Autofill provider code change appears necessary for the field-focus trigger.

WebView initialization: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/android_webview/browser/aw_contents.cc#392>

Installed M133 gate: <https://chromium.googlesource.com/chromium/src/+/49ec12cc413ffec766028509968b31d7d65fa0b7/components/android_autofill/browser/android_autofill_provider.cc#110>

Current focus trigger: <https://chromium.googlesource.com/chromium/src/+/ddce8a4224e29dd3d8e2010d3053ce52aff7fa9b/components/android_autofill/browser/android_autofill_provider.cc#596>

### 6. Android framework is not the conditional-mediation blocker

At AOSP revision `1cdfff...`:

- `CredentialManager.prepareGetCredential()` performs a UI-free preparation request and returns `PrepareGetCredentialResponse`;
- `PendingGetCredentialHandle` later launches the remaining retrieval flow;
- `GetCredentialRequest.Builder.setOrigin()` is available to a browser with `CREDENTIAL_MANAGER_SET_ORIGIN`;
- that permission is protection level `normal`.

There is no `WebView`, `isChrome`, or conditional-mediation check in these framework entry points. Chromium is responsible for mapping WebAuthn conditional mediation to this generic framework protocol.

Framework API: <https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/credentials/CredentialManager.java#287>

Origin permission: <https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/res/AndroidManifest.xml#5103>

### 7. AndroidX cannot add this behavior by itself

AndroidX WebKit selects `APP` or `BROWSER` WebAuthn mode through the installed WebView support-library boundary. It does not implement Credential Manager prefetch, hold a pending WebAuthn request, observe the Chromium Autofill field lifecycle, or supply a candidate UI. Official Android documentation also states that the WebKit library does not support `mediation: "conditional"`.

Official guide: <https://developer.android.com/identity/sign-in/credential-manager-webview>

## Proposed minimal patch

Target current Chromium revision `ddce8a...`, API 34+ only, and initially expose the OS Credential Manager sheet on a focused `autocomplete="username webauthn"` field. Do not attempt to port Chrome keyboard accessory/touch-to-fill UI in the first experiment.

### Patch A: report support only for the new, narrow WebView route

In `AuthenticatorImpl.couldSupportConditionalMediation()`:

- preserve the existing Chrome predicate;
- add `WebauthnMode.BROWSER` only when Android is API 34+, `getCredManSupportForWebView()` is `FULL_UNLESS_INAPPLICABLE`, and a new WebView-conditional feature flag is enabled;
- do not require GMS WebAuthn support for the OS-Credential-Manager-only branch;
- keep `APP`, `NONE`, and pre-API-34 WebView false.

Pseudo-code (not an applied patch):

```java
if (isChrome(webContents)) {
    return GmsCoreUtils.isWebauthnSupported();
}
return WebViewConditionalFeature.enabled()
        && is(webContents, WebauthnMode.BROWSER)
        && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        && CredManSupportProvider.getCredManSupportForWebView()
                == CredManSupport.FULL_UNLESS_INAPPLICABLE;
```

### Patch B: route `BROWSER + CONDITIONAL` through prefetch

In the non-Chrome branch of `Fido2CredentialRequest.handleGetAssertionRequest()`:

- before the existing `NOT_IMPLEMENTED`, recognize only the API 34+ feature-gated `BROWSER + CONDITIONAL + full CredMan` case;
- reset the barrier to `ONLY_CRED_MAN`;
- call `mCredManHelper.startPrefetchRequest(...)` using the browser origin/client-data values;
- return without calling direct `startGetRequest()`;
- retain `NOT_IMPLEMENTED` for APP, pre-API-34 BROWSER, disabled feature, and unsupported backends.

This is the semantic core of the change.

### Patch C: make the CredMan-only bridge usable without Chrome UI

In `Fido2CredentialRequest.getBridge()`, allow a bridge for the same feature-gated `BROWSER` route.

Preferred implementation for reviewability:

1. In `webauthn_browser_bridge.cc`, route CredMan-only methods (`OnCredManConditionalRequestPending`, `OnCredManUiClosed`, `CleanupCredManRequest`, and passkey-only cleanup) directly to `WebAuthnCredManDelegateFactory`, because their current `WebAuthnClientAndroid` base implementations only do that forwarding and are not virtual.
2. Guard Chrome-custom methods (`OnCredentialsDetailsListReceived`, generic `CleanupWebAuthnRequest`) with `WebAuthnClientAndroid::HasClient()` before calling `GetClient()`. WebView must never enter the pre-Android-14 credential-enumeration/custom-picker path.

Alternative implementation: add `AwWebAuthnClientAndroid` under `android_webview/browser/`, register it in `AwBrowserMainParts::PreMainMessageLoopRun()`, and implement the abstract Chrome-UI methods as guarded no-ops. This is mechanically straightforward but creates an embedder client whose only useful work is already implemented in the common non-virtual base class.

### Patch D: M133-only Autofill gate

If the treatment must be based on installed revision `49ec12...`, also remove or replace the `kAutofillVirtualViewStructureAndroid` check in `AllowCredManOnField()`. The delegate's `kNotReady` state still prevents a sheet when no conditional WebAuthn request exists. Current Chromium already removed this check, so this patch is unnecessary on `ddce8a...`.

### Changes explicitly not recommended

- Do not redefine `WebauthnModeProvider.isChrome()` to include `BROWSER`.
- Do not make the WebView app select global `CHROME` mode.
- Do not copy `ChromeWebAuthnClientAndroid` or Chrome Password Manager UI for the first API-34 experiment.
- Do not weaken GPM privileged-browser, origin, signature, device-lock, or WebView-provider checks.
- Do not replace only `libwebviewchromium.so`; build/install the complete compatible WebView provider APK and resources.

Those broad mode changes would also select Chrome/GPM request decorators and Chrome-only UI/lifecycle assumptions unrelated to the desired OS CredMan flow.

## Build and treatment plan

1. Use a current Chromium checkout pinned to the chosen treatment commit, `target_os="android"`, `target_cpu="arm64"`.
2. Build `system_webview_apk` (and targeted unit/JUnit tests first).
3. Run it on an API 34+ AOSP `userdebug` arm64 emulator. The current `user` Google image is a control, not a viable local-provider treatment image.
4. Install/switch using Chromium's generated `system_webview_apk` wrapper and verify `dumpsys webviewupdate` reports the patched version.
5. Reinstall the unchanged test-browser APK, verify support mode remains `BROWSER=2`, then repeat the Railway page test.
6. Use an authorized credential provider whose privileged-caller allowlist contains the browser package/signature. For Google Password Manager, obtain approval for the intended release identity rather than bypassing the allowlist.

Official WebView build guide: <https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/build-instructions.md>

## Required tests

Add or extend these existing suites:

- `components/webauthn/android/junit/.../AuthenticatorImplTest.java`
  - BROWSER + API 34+ + feature/full CredMan reports conditional available;
  - APP, pre-34, and disabled feature report false.
- `components/webauthn/android/junit/.../Fido2CredentialRequestRobolectricTest.java`
  - BROWSER conditional calls `prepareGetCredential`, not direct `getCredential` and not `NOT_IMPLEMENTED`;
  - ordinary BROWSER behavior remains unchanged.
- `components/webauthn/android/junit/.../cred_man/CredManHelperRobolectricTest.java`
  - prepared result stores a deferred callback and field trigger starts the full request once.
- `components/android_autofill/browser/android_autofill_provider_unittest.cc`
  - focused `autocomplete=webauthn` field with ready delegate triggers CredMan;
  - no request/not-ready/wrong field does not trigger.
- `android_webview/javatests/.../WebAuthnTest.java` and `AwAutofillTest.java`
  - end-to-end WebView mode/lifecycle regression coverage with a test provider or fake bridge.

Device acceptance criteria:

1. stock WebView control remains `Autofill 未対応`;
2. patched WebView returns conditional availability true;
3. page load performs prefetch without showing UI;
4. focusing the username field opens the OS Credential Manager selector;
5. selecting an allowlisted passkey completes assertion for the Railway RP;
6. cancellation/navigation cleans the pending request without a stale sheet or crash;
7. ordinary create/get still behave as before.

## Result and causal assessment

High-confidence causal chain for the current failure:

```text
Web page conditional availability check
  -> AuthenticatorImpl requires isChrome
  -> BROWSER returns false

If the page forces the request anyway
  -> Fido2CredentialRequest non-Chrome conditional
  -> NOT_IMPLEMENTED before Credential Manager

If only that rejection is removed
  -> ordinary WebView direct get path
  -> wrong conditional timing and no deferred Autofill callback

Correct API 34+ treatment
  -> prepareGetCredential
  -> WebAuthnCredManDelegate stores pending callback
  -> AndroidAutofillProvider sees autocomplete=webauthn on focus
  -> pending-handle getCredential opens OS sheet
```

The Android framework supplies the required primitive and is not the behavior blocker. Chromium WebView integration intentionally omits the conditional route and Chrome bridge/UI. Current Chromium has already generalized the Android Autofill field trigger, reducing the API-34 prototype to a WebAuthn routing/bridge change.

This conclusion does not mean the current test browser can use Google Password Manager immediately after a WebView patch. GPM separately rejected the app's asserted RP origin because the package/signing certificate is not in its privileged-browser allowlist. The Android `normal` permission authorizes setting an origin at the framework API boundary; it does not compel a provider to trust that caller.

Official privileged-app guidance: <https://developer.android.com/identity/sign-in/privileged-apps>

## Remaining uncertainty and next experiment

- The source proposal has not yet been compiled, so JNI/BUILD dependency details and cleanup lifecycle require targeted tests.
- Current-main Android Autofill code looks sufficient for OS-sheet triggering, but a patched provider must confirm that WebView's Autofill manager delivers the field focus after the prefetch result on the exact API-36 image.
- An AOSP `userdebug` emulator will not include Google Password Manager by default. Use a test credential provider that explicitly authorizes the browser identity for the first end-to-end routing proof.
- Google Password Manager end-to-end validation requires its documented privileged-browser approval with the intended release certificate.
- Pre-Android-14 conditional UI is a different, much larger project: it needs credential enumeration plus an embedder-owned candidate picker/keyboard-accessory UI. It is intentionally excluded from the minimal patch.
- Chrome-style inline candidate chips and password merging are also excluded. The proposed success UI is the Android 14+ OS Credential Manager sheet launched on field focus.

Smallest falsifying next experiment:

1. patch current Chromium main with A-C behind a disabled-by-default feature;
2. run the focused Java/C++ tests;
3. build `system_webview_apk` only, not a full AOSP image;
4. install it on an API-36 AOSP `userdebug` emulator with an authorized test provider;
5. prove that load is silent and field focus launches the pending CredMan assertion.

## Artifacts and hashes

Paths are relative to `artifacts/webview-passkey-autofill-source-20260819/`.

- `device-control/screen.png`: `4fec1197135a74b732115756f4b58d1e5680599e35d734b2ccb2279fe9de9551`
- `device-control/ui.xml`: `f9c21f442416f5a9ffdd2bbead14063c0de90634f0075f9d5eddae33dd68a453`
- AndroidX WebKit 1.14.0 AAR: `265604786ea1c9679e3f860f7f13072375c141f46db9092ed8ef5ecd599a516d`
- Prior ordinary-WebAuthn/GPM evidence: `artifacts/webview-passkey-api36-20260819/`
- Prior Chrome control: `artifacts/chrome-passkey-api36-20260819/`

## Tests and warnings

- ADB observe/verify control passed after manual unlock: foreground activity was `com.example.webviewpasskeybrowser.browser/.MainActivity`; UI hierarchy contained `WebAuthn 対応` and `Autofill 未対応`.
- No source patch, Chromium checkout, compilation, APK replacement, credential creation, or provider configuration was performed in this investigation.
- The current emulator display size was not overridden, so no display reset was necessary.
- Do not generalize M133 feature-gate details to current Chromium; both revisions are documented separately above.
- Do not treat a positive conditional-availability result alone as success. The treatment must prove silent prefetch, focus-triggered UI, assertion completion, and cleanup.

## GCP resources and cleanup

- GCP resources created: none.
- GCP resources removed: none.
- GCP audit: not applicable; only local source reads and an existing emulator were used.
