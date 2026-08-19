# WebView passkey test browser

This Android app compares the same WebView page in two modes:

- `controlDebug` keeps WebView's default web-authentication support.
- `browserDebug` enables AndroidX WebKit's
  `WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER` mode and declares the two normal Credential Manager
  permissions required for browser-origin and conditional-candidate queries.

Both flavors load the Railway passkey test site by default and log WebAuthn capability probes under
the `WebViewPasskey` tag. The browser flavor is intentionally a test harness, not a hardened general
purpose browser.

## Build

```sh
./gradlew :app:assembleControlDebug :app:assembleBrowserDebug \
  :app:testControlDebugUnitTest :app:testBrowserDebugUnitTest
```

The paired AOSP test provider authorizes the exact browser signing certificate. When rebuilding with
a different debug key, update the test-only fingerprint as described in
`../test-credential-provider/README.md`.

## Chromium treatment

Ordinary Android WebView does not expose the conditional passkey path tested here. Apply
`../patches/chromium-webview-browser-conditional.patch` to the pinned Chromium revision recorded in
the investigation memo, build `system_webview_apk`, and run control and treatment on the same
AOSP `userdebug` image.

The patch keeps `WebauthnMode.BROWSER`; it does not opt the app into Chromium's `CHROME` or
`CHROME_3PP_ENABLED` modes. The successful control/treatment results, revisions, hashes, and device
steps are in `../artifacts/webview-conditional-cuttlefish-20260819/investigation.md`.
