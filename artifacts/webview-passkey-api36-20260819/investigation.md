# WebView browser passkey experiment on Android 16 emulator

- Date: 2026-08-19 (Asia/Tokyo)
- Status: complete
- Hypothesis: AndroidX WebKit browser mode makes ordinary WebAuthn create/get available in WebView, but Google Password Manager rejects the unapproved custom browser identity; conditional mediation remains unavailable.
- Result: supported on the pinned configuration.

## Question and scope

Can a small browser app backed by Android WebView use passkeys against `https://passkey-test-lab-production.up.railway.app/` on the running Android emulator?

The experiment keeps four cases separate:

1. availability of ordinary WebAuthn `create()` and `get()` in a default WebView;
2. availability after enabling AndroidX WebKit's browser WebAuthentication mode and origin permission;
3. Google Password Manager's privileged-browser approval of the calling package/signing identity;
4. conditional mediation/Autofill UI.

No AOSP, Chromium, WebView, or provider trust check was changed or bypassed. Chrome results from the preceding experiment are used only as an RP/device control; the Play-services version changed between that run and this run and is disclosed below.

## Configuration

### Local and upstream revisions

- Local repository: `git@github.com:YusukeIwaki/aospman.git`
- Local starting revision: `a4f7863ae52c91e31dd525be9a843cb055a74d7d`
- New app (uncommitted at the time of the run): `webview-passkey-browser/`
- Android CLI: `1.0.15985488`
- Gradle wrapper: 9.1.0; Android Gradle Plugin: 9.0.1; Java: 17; compile/target SDK: 36; min SDK: 28
- AndroidX WebKit: `1.14.0`
- AndroidX Credentials and Play-services auth bridge: `1.6.0-beta02`
- Chromium source pinned during source reading: `https://chromium.googlesource.com/chromium/src` at `0dc2402207864c99a546c597ce6fc45aab541d26`
  - `components/webauthn/android/webauthn_mode.h`, `WebauthnMode`: `NONE`, `APP`, `BROWSER`, `CHROME`, `CHROME_3PP_ENABLED`
  - `components/webauthn/android/README.md`: WebView/browser mode routes Android 14+ operations to Credential Manager; the Chrome browser bridge/UI is separate from WebView.
- AOSP source pinned during source reading: `https://android.googlesource.com/platform/frameworks/base` at `1cdfff555f4a21f71ccc978290e2e212e2f8b168`
  - `core/res/AndroidManifest.xml`, `android.permission.CREDENTIAL_MANAGER_SET_ORIGIN`: protection level `normal`.

### Device, apps, and provider

- AVD: `medium_phone`, serial `emulator-5554`, Android 16 / API 36 / `arm64-v8a`
- Build fingerprint: `google/sdk_gphone64_arm64/emu64a:16/BE2A.250530.026.D1/13818094:user/release-keys`
- Android System WebView: `com.google.android.webview` 133.0.6943.137 (`versionCode=694313732`)
- Installed Chrome at the end of this run: `com.android.chrome` 151.0.7922.137 (`versionCode=792213733`)
- Google Play services: 26.31.31 (260400-959389638), `versionCode=263131035`
- Credential provider component: `com.google.android.gms/.auth.api.credentials.credman.service.PasswordAndPasskeyService`
- Credential provider: Google Password Manager; account identity omitted.
- Control package: `com.example.webviewpasskeybrowser.control`; no `CREDENTIAL_MANAGER_SET_ORIGIN`; WebAuthentication support left at default.
- Treatment package: `com.example.webviewpasskeybrowser.browser`; declares `android.permission.CREDENTIAL_MANAGER_SET_ORIGIN`; calls `WebSettingsCompat.setWebAuthenticationSupport(...WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER)`.
- Both APKs use the same Android debug certificate SHA-256: `D6:B8:90:EC:A6:F4:70:8A:FF:24:BE:19:17:6C:56:AF:EE:38:D8:D4:D5:61:2A:99:64:F5:F5:81:CC:C2:B4:B1`.

### Relying party

- Origin: `https://passkey-test-lab-production.up.railway.app`
- RP ID: `passkey-test-lab-production.up.railway.app`
- The immediately preceding Chrome run completed ordinary create/get and conditional login on this AVD; see `artifacts/chrome-passkey-api36-20260819/investigation.md`.
- Version drift: that Chrome run recorded Chrome 133.0.6943.137 and Play services 25.08.34. Chrome and Play services were updated before the final WebView evidence. Therefore it is a strong RP/device sanity check, not a perfectly version-matched provider control.

## Experiment design and results

| Case | Control or treatment | Expected falsifier | Result |
| --- | --- | --- | --- |
| Default WebView | Control package, same page/device/WebView | `PublicKeyCredential` exists without opt-in | Falsified: WebKit feature exists, configured support is `0`, and the page reports `WebAuthn 非対応` |
| WebView browser mode | Treatment package plus origin permission | Browser mode still does not expose WebAuthn | Falsified: configured support is `2`; page reports `WebAuthn 対応` |
| Ordinary `get()` | Treatment, Credential Manager, GPM | GPM accepts asserted RP origin for the custom app | Falsified: call reaches Credential Manager, then GPM rejects package/certificate as not a trusted browser |
| Ordinary `create()` | Treatment, Credential Manager, GPM | GPM accepts asserted RP origin for the custom app | Falsified: call reaches Credential Manager, then the same trusted-browser rejection occurs |
| Conditional mediation | Treatment | `isConditionalMediationAvailable()` returns true and a candidate is offered on focus | Falsified: method exists but returns false; page reports `Autofill 未対応`; no conditional candidate appears |

## Reproduction

Create, build, install, and launch:

```text
android create empty-activity --name=WebViewPasskeyBrowser --output=webview-passkey-browser --minSdk=28 --verbose

cd webview-passkey-browser
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
PATH=/opt/homebrew/opt/openjdk@17/bin:/usr/bin:/bin:/usr/sbin:/sbin \
./gradlew --no-daemon \
  :app:testControlDebugUnitTest :app:testBrowserDebugUnitTest \
  :app:assembleControlDebug :app:assembleBrowserDebug

android install --device=emulator-5554 \
  --apks=app/build/outputs/apk/control/debug/app-control-debug.apk \
  --install-options=-r
android install --device=emulator-5554 \
  --apks=app/build/outputs/apk/browser/debug/app-browser-debug.apk \
  --install-options=-r

adb -s emulator-5554 shell am start \
  -n com.example.webviewpasskeybrowser.control/com.example.webviewpasskeybrowser.MainActivity
adb -s emulator-5554 shell am start \
  -n com.example.webviewpasskeybrowser.browser/com.example.webviewpasskeybrowser.MainActivity
```

For each package, wait for the page to load and inspect the mode/status line plus the site's WebAuthn and Autofill badges. In the treatment, an explicit `navigator.credentials.get()` and `create()` can be initiated from the page. The deployed registration UI defect described below must first be avoided or fixed for the create path.

## Observations and evidence

### Default control

- App log: `DEFAULT control feature=true support=0 provider=com.google.android.webview@133.0.6943.137`.
- The page reports `WebAuthn 非対応` and `Autofill 未対応`.
- Evidence: `30_control_final/screen.png`, `30_control_final/ui.xml`, `30_control_final/logcat.txt`.

This establishes that merely embedding the page in WebView is insufficient even though the installed WebView advertises AndroidX's WebAuthentication feature.

### Browser-mode treatment

- App log: `BROWSER treatment feature=true support=2 provider=com.google.android.webview@133.0.6943.137`.
- The page reports `WebAuthn 対応` and `Autofill 未対応`.
- The JavaScript capability check records `navigator.credentials` present and `PublicKeyCredential.isConditionalMediationAvailable` present; the page's awaited availability check returns false.
- Evidence: `31_browser_final/screen.png`, `31_browser_final/ui.xml`, `31_browser_final/logcat.txt`.

### Ordinary get rejection

The treatment reaches the platform/provider path:

```text
CredentialManager: starting executeGetCredential with callingPackage: com.example.webviewpasskeybrowser.browser
FetchAllowlistedOriginOperation: rejecting asserted origin ... because it is not in the list of trusted browsers.
IllegalStateException: Origin is not being returned as the calling app did not match the privileged allowlist
cr_CredManHelper: ... GetCredentialException.TYPE_NO_CREDENTIAL
```

The web-visible result is `NotAllowedError`. Full evidence: `29_browser_login_cdp_logcat.txt`. The earlier manual site flow produced the same provider rejection and a humanized cancel/timeout message.

### Ordinary create rejection

The treatment also reaches the platform/provider create path:

```text
CredentialManager: starting executeCreateCredential with callingPackage: com.example.webviewpasskeybrowser.browser
FetchAllowlistedOriginOperation: rejecting asserted origin ... because it is not in the list of trusted browsers.
IllegalStateException: Origin is not being returned as the calling app did not match the privileged allowlist
cr_CredManHelper: ... CreateCredentialException.TYPE_NO_CREATE_OPTIONS
```

The web-visible result is `NotReadableError`. Full evidence: `27_browser_register_cdp_logcat.txt`.

### Separate Railway test-harness defect

The deployed `/app.js` is older than the checked-out source:

- deployed SHA-256: `b5fcbdae31dfc77df283fd6f96634e6dc86d191381913e9e09e0b82a641fe8d9`;
- checked-out `passkey-test-site/public/app.js` SHA-256: `117227dea510330cb428183a8053a035d4e7dec5bf52ee1af76432dfc5e80391`.

In the deployed registration handler, `setBusy(form, true)` disables the input before `new FormData(form).get("username")`. A DevTools fetch wrapper observed the resulting request body as `{"username":null}` although the DOM input and a separately created `FormData` both contained the visible 13-character value. Directly posting that same DOM value returned HTTP 200 options. The experiment then invoked `navigator.credentials.create()` with those options and captured the provider rejection above. This workaround was tab-local, did not alter provider checks, and did not prove the deployed UI is correct.

The checked-out source already reads the username before disabling the form. Railway should be redeployed from that source before future UI-only reproduction.

## Result and causal assessment

The hypothesis is supported with high confidence for this pinned device/provider combination.

1. Default WebView fails before Credential Manager because WebAuthentication support remains `NONE`/`0`.
2. AndroidX WebKit browser mode plus `CREDENTIAL_MANAGER_SET_ORIGIN` exposes ordinary WebAuthn and routes create/get to Credential Manager.
3. The permission and browser mode are necessary but not sufficient for Google Password Manager. GPM independently rejects the custom package and debug signing certificate because they are not in its privileged browser allowlist.
4. Conditional mediation is a different limitation. AndroidX WebKit reports it unavailable, and the WebView integration does not provide Chrome's conditional/Autofill browser UI.
5. The RP server is not the primary blocker: Chrome previously completed the ceremonies, and both WebView treatment calls receive server options and fail later inside GPM's origin-allowlist operation.

No passkey was created by the WebView app. Registration-options requests may have left provider-less test-user records in the test service; production storage was not inspected.

## Remaining uncertainty and next experiment

- The result does not prove all credential providers reject custom WebView browsers; it proves Google Password Manager rejects this unapproved package/signing identity.
- The smallest ordinary-WebAuthn follow-up is to test the same treatment APK with an authorized credential provider that explicitly allowlists the package and certificate, or to complete Google's browser approval process with the intended release identity. Re-run create and get unchanged.
- A release-signed approved build is required to distinguish app implementation from GPM approval; weakening signature/origin/provider checks is out of scope.
- Conditional UI should be treated as a separate Chromium/browser-layer experiment. Provider approval alone is not expected to add Chrome's WebAuthn browser bridge or Autofill UI to WebView.
- Re-run after deploying the already-fixed `passkey-test-site/public/app.js`, so no DevTools workaround is needed.
- WebView 133 is old relative to the test date. Repeat on a current WebView before generalizing beyond this pinned image.

## Artifacts and hashes

- `apks/app-browser-debug.apk`: `5d1e2a1caf1070143c330ef243f0b61d800d46c5a63ecf0a6b9e7a4cb0497a88`
- `apks/app-control-debug.apk`: `e613a2895de7d36690379864039f6915d579608e15087e3914c5fb15ff756a32`
- `27_browser_register_cdp_logcat.txt`: `b9672724f00df6c12289eed4bd365e8914133081a9563a709267ae28d9bfef82`
- `29_browser_login_cdp_logcat.txt`: `8502dc804461502a5c52ca97095e05ea248c53cceefdbb4c814bb20505dd0583`
- `30_control_final/screen.png`: `d973d38ab381f4d09c18b16266a79a4a053d2e0986e7606ddb8e92e1926707c7`
- `30_control_final/logcat.txt`: `6210021d5a235cab2bdd43e2c40367341d3b908c9bd1030ae74035308c013e55`
- `31_browser_final/screen.png`: `d4c69bd9104adbee9ffbc0e20ccd00077c74536f0f1c1b29ebfa7838aa233be6`
- `31_browser_final/logcat.txt`: `fcfcead087074de8bf70b20f8f6cf28d46800e8328f02f6202c4995a701b2810`

Paths above are relative to `artifacts/webview-passkey-api36-20260819/`.

## Tests and warnings

- `testControlDebugUnitTest`: passed.
- `testBrowserDebugUnitTest`: passed.
- `assembleControlDebug`: passed.
- `assembleBrowserDebug`: passed.
- `lintControlDebug`: passed.
- `lintBrowserDebug`: passed.
- Final APKs were reinstalled with Android CLI delta install and verified with `apksigner`.
- Build warning: installed command-line tooling encountered SDK XML version 4 while understanding up to version 3; build and tests still completed successfully.
- Emulator DNS intermittently failed when using the default DNS proxy. The emulator was restarted with explicit DNS `8.8.8.8`; hostname resolution then succeeded. Network failures were kept separate from passkey results.
- The emulator remains running with the browser-treatment app in the foreground. Account identity and device-unlock secret are intentionally omitted.

## GCP resources and cleanup

- GCP resources created: none.
- GCP resources removed: none.
- GCP audit: not applicable; this was a small local app build and emulator experiment.
