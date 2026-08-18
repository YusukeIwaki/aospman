# Android passkey architecture baseline

Use this as a working model for hypothesis design, not as timeless truth. Before citing a symbol, claiming support, or designing a patch, pin the relevant AOSP, Chromium, AndroidX, and Android documentation revisions and verify the statement there.

## Separate the mechanisms

Do not collapse these into one “passkey support” result:

| Boundary | Question | Typical owner |
| --- | --- | --- |
| Ordinary WebAuthn | Does `navigator.credentials.create/get()` reach an authenticator? | Blink, Chromium WebAuthn, WebView embedder |
| Browser-origin delegation | May the browser call on behalf of the displayed web origin? | WebView browser mode, Android permission, Credential Manager |
| Provider trust | Will the credential provider accept this browser package/signature? | Credential provider policy and approval |
| Conditional UI | Does `mediation: "conditional"` bind passkeys to a focused login field? | Browser UI, Password Manager, Autofill |

An API dispatch can succeed while provider trust or conditional UI still fails. Conversely, provider rejection does not prove that the WebAuthn route is absent.

## Ordinary WebAuthn in a WebView browser

The baseline Chromium model has Android WebAuthn modes such as `NONE`, `APP`, `BROWSER`, `CHROME`, and `CHROME_3PP`. A newly-created WebView is not automatically equivalent to Chrome; WebView WebAuthn support has historically defaulted to `NONE` until the embedder selects the appropriate mode.

For a browser-style WebView app, test the supported AndroidX WebKit API before changing Chromium:

```xml
<uses-permission android:name="android.permission.CREDENTIAL_MANAGER_SET_ORIGIN" />
```

```kotlin
if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_AUTHENTICATION)) {
    WebSettingsCompat.setWebAuthenticationSupport(
        webView.settings,
        WebSettingsCompat.WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER
    )
}
```

At the baseline revision, browser mode routes Android 14+ through Credential Manager and older Android versions through the applicable GMS FIDO2 browser API. Verify this split for the pinned Chromium branch. Also verify the current AOSP protection level and enforcement points for `CREDENTIAL_MANAGER_SET_ORIGIN`; it has been a normal permission, but that does not replace provider-side caller trust.

## Provider trust and Google Password Manager

A browser acts on behalf of an arbitrary web origin, so the credential provider must trust the browser package and signing identity as a privileged caller. This decision is outside the WebView binary.

Google Password Manager has required third-party browsers to obtain provider approval for arbitrary web-origin credential access. Treat approval/allowlisting as an external product prerequisite. Building Chromium or WebView does not grant it, and experiments must not patch around provider checks.

## Conditional mediation and Chrome UI

Ordinary WebAuthn and passkey autofill are separate features. The autofill experience associated with a focused username/password field normally uses:

```javascript
navigator.credentials.get({ publicKey: options, mediation: "conditional" })
```

The baseline Android WebView documentation states that WebView does not support conditional mediation. Re-check the current documentation and source before relying on that result.

In Chromium, trace `WebauthnBrowserBridge` and its Chrome-side controllers. At the baseline revision, this bridge is for `CHROME`/`CHROME_3PP`, is not used by Android WebView, and coordinates Chrome credential-selection UI with Password Manager, Autofill, keyboard accessory, or touch-to-fill paths. Therefore explicit create/get working in WebView does not imply Chrome-style passkey autofill.

## Custom WebView provider scope

Do not model WebView as one replaceable `libwebviewchromium.so`. A provider artifact can couple:

- Java/DEX and native libraries;
- resources, `.pak` files, ICU data, and V8 snapshots;
- manifest metadata, provider package name, target SDK, and signatures;
- framework provider selection and allowlists.

Production `user` builds enforce provider identity and signing constraints. Use an authorized `userdebug` or `eng` system for custom-provider experiments and record the selected provider. Never claim that a standalone `.so` replacement is sufficient without proving compatibility across the complete provider artifact.

Porting Chrome-style conditional passkey UI into WebView is a browser-layer project, not a small native-library toggle. Expect to trace or adapt code across `components/webauthn/android`, Chrome Android WebAuthn controllers, Password Manager, Autofill, JNI/Java UI, and the WebView embedder boundary.

## Smallest baseline checks

Before building Chromium or AOSP, record and test:

1. `WebViewFeature.WEB_AUTHENTICATION` support;
2. `WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER` configuration;
3. `CREDENTIAL_MANAGER_SET_ORIGIN` in the app manifest;
4. browser package/signing identity and credential-provider approval;
5. explicit create/get separately from conditional mediation;
6. Android 13-or-earlier and Android 14+ when backend routing matters.

## Upstream anchors

- Chromium Android WebAuthn: <https://chromium.googlesource.com/chromium/src/+/HEAD/components/webauthn/android/>
- Chromium `AwSettings`: <https://chromium.googlesource.com/chromium/src/+/HEAD/android_webview/java/src/org/chromium/android_webview/AwSettings.java>
- Chromium WebView provider documentation: <https://chromium.googlesource.com/chromium/src/+/HEAD/android_webview/docs/webview-providers.md>
- Chromium WebView loading documentation: <https://chromium.googlesource.com/chromium/src/+/HEAD/android_webview/docs/how-does-loading-work.md>
- AOSP platform manifest: <https://android.googlesource.com/platform/frameworks/base/+/master/core/res/AndroidManifest.xml>
- Android privileged Credential Manager callers: <https://developer.android.com/identity/sign-in/privileged-apps>
- Android Credential Manager in WebView: <https://developer.android.com/identity/sign-in/credential-manager-webview>

Use `references/experiment-matrix.md` to turn this model into a controlled experiment.
