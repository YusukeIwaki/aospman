# Passkey experiment matrix

## Track A: ordinary WebAuthn in a WebView browser

Test before source modification.

| Variable | Control | Treatment |
| --- | --- | --- |
| WebAuthn support | default/`NONE` or app mode | AndroidX WebKit browser mode |
| Manifest | without browser-origin permission | `android.permission.CREDENTIAL_MANAGER_SET_ORIGIN` declared |
| Android | API 33 or earlier | API 34+ as a second routing case |
| Operation | `navigator.credentials.create()` | `navigator.credentials.get()` |

Capture `WebViewFeature.WEB_AUTHENTICATION`, WebView package/version, AndroidX WebKit version, app package/signature, origin, provider, JS exception/result, and logcat.

Current upstream starting points:

- `android_webview/java/src/org/chromium/android_webview/AwSettings.java`
- `android_webview/support_library/java/src/org/chromium/support_lib_glue/SupportLibWebSettingsAdapter.java`
- `components/webauthn/android/README.md`
- AndroidX WebKit `WebSettingsCompat` and `WebViewFeature`
- AOSP `frameworks/base/core/res/AndroidManifest.xml`

## Track B: provider trust and browser approval

Keep the browser implementation constant and vary only the credential provider or its authorized-browser configuration. Distinguish:

- origin delegation reaching Credential Manager;
- provider accepting the caller package/signature;
- credentials existing for the RP/account;
- user cancellation or UV failure.

Do not patch around provider checks. Google Password Manager approval is external to a custom WebView/Chromium binary and must be treated as a product/provider prerequisite.

## Track C: conditional mediation and Autofill UI

Use a page that supports both an explicit WebAuthn request and `mediation: "conditional"`. Compare Chrome, stock WebView browser mode, and the custom build on the same device/provider.

Trace these current upstream areas at the pinned revision:

- `components/webauthn/android/`
- `components/webauthn/android/webauthn_browser_bridge.h`
- Java/C++ files defining `WebauthnBrowserBridge`
- Chrome Android WebAuthn UI controllers
- Chrome Password Manager and Autofill integration reached from the focused input field

The upstream `components/webauthn/android/README.md` currently describes `WebauthnBrowserBridge` as Chrome-only (`CHROME`/`CHROME_3PP`) and not used by Android WebView. Verify that statement at the pinned revision before designing the patch: <https://chromium.googlesource.com/chromium/src/+/HEAD/components/webauthn/android/>

## Track D: custom WebView provider

Build a complete provider artifact appropriate to the branch. Record:

- provider APK target and package name;
- Java/DEX and native revisions;
- resources, `.pak`, ICU/V8 data, and manifest metadata;
- device AOSP build type and provider allowlist/signature behavior;
- selected provider reported by platform tools.

Use `userdebug` or `eng` only for an authorized test system. Compare stock and modified providers on the same system image. Start with the WebView provider documentation: <https://chromium.googlesource.com/chromium/src/+/HEAD/android_webview/docs/webview-providers.md>

## Track E: AOSP framework image

Use only when the experiment changes framework permissions, Credential Manager integration, provider selection, or other platform behavior. Pin the AOSP manifest and product target. Build `userdebug`, retain the manifest revision and patch, and state whether verified boot/data wipe affected comparability.

## Result template

```text
Hypothesis:
Pinned revisions:
Device/system image:
Browser/WebView package and signing identity:
Credential provider:
RP origin:
Control:
Treatment:
Observed JS/API result:
Observed UI/logcat:
Conclusion:
Alternative explanations:
Artifacts and SHA-256:
Next smallest experiment:
Cloud resources created/deleted:
```
