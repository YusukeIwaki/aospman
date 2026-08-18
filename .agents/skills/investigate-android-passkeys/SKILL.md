---
name: investigate-android-passkeys
description: Investigate, modify, build, and test Android passkey behavior across AOSP, Android WebView, Chromium, custom browser apps, WebAuthn, Credential Manager, Autofill, and conditional mediation. Use for source tracing, hypothesis design, experiment matrices, targeted Chromium/AOSP patches, custom WebView provider work, APK/system-image builds, or adb validation involving passkeys. Do not use for unrelated Android authentication or generic browser development.
---

# Investigate Android Passkeys

Separate mechanisms before changing code. Ordinary WebAuthn, browser-origin delegation, credential-provider trust, conditional mediation, and Chrome's password/autofill UI have different owners and failure modes.

## Begin with evidence

1. Read the root `MEMO.md` completely.
2. State one falsifiable question and the smallest experiment that can answer it.
3. Fetch current upstream source, then pin and record the exact commit/tag before citing paths or building.
4. Read `references/experiment-matrix.md` and select the applicable track.
5. Record Android API level, system build, WebView/Chrome version, app package and signing certificate, credential provider, RP origin, source revision, and relevant feature flags.

Treat `MEMO.md` as a researched hypothesis. Correct it when current source or results disagree.

## Choose the cheapest valid track

1. **App-only baseline:** Configure AndroidX WebKit browser-mode WebAuthn and `CREDENTIAL_MANAGER_SET_ORIGIN`; test ordinary create/get before modifying Chromium.
2. **Targeted Chromium browser build:** Use this when the hypothesis concerns Chrome/Chromium browser-layer UI, conditional mediation, password retrieval, Autofill, or `WebauthnBrowserBridge`.
3. **Targeted WebView provider build:** Use this when the hypothesis concerns `android_webview`, support-library glue, `AwSettings`, or WebView-specific routing.
4. **AOSP `userdebug` image:** Use only when provider selection/signature checks, framework permissions, system integration, or a modified platform component is essential.

Do not begin with a full AOSP build merely to test browser-mode WebAuthn. Do not assume a native `.so` replacement is a complete WebView provider experiment; Java/DEX, resources, data files, manifest metadata, package selection, and signatures can be coupled.

## Trace both control planes

For each hypothesis, trace:

- the web call from Blink/content into Android WebAuthn routing;
- the selected mode (`NONE`, `APP`, `BROWSER`, `CHROME`, or `CHROME_3PP`);
- the Android-version-dependent backend (Credential Manager versus GMS FIDO2 where applicable);
- origin delegation and caller/provider trust;
- any Chrome-only browser bridge, Password Manager, Autofill, keyboard accessory, or touch-to-fill path.

Validate current locations rather than relying on memorized paths. Start at the upstream directories and files listed in `references/experiment-matrix.md`.

## Build remotely

Use `$manage-aosp-spot-build` for large checkouts and builds. Run its audit and preflight before creating a VM. Pin revisions, commit or export patches early, build the narrowest target, retrieve evidence and artifacts, then delete the VM and audit again.

Likely targets include a custom browser APK, `chrome_public_apk`, a WebView provider APK, or an AOSP `userdebug` image. Confirm the correct target for the pinned branch with `gn ls`, build documentation, or AOSP product configuration; do not copy a stale command blindly.

## Validate

- Use the same device/image and RP for control and treatment when possible.
- Cover Android 13 or earlier and Android 14+ when backend routing is material.
- Test ordinary `navigator.credentials.create/get` separately from `mediation: "conditional"`.
- Capture JS result/error, logcat, visible UI, provider selection, package versions, and source revision.
- Use the `android-adb-ui-debugger` skill when driving a connected Android UI or collecting adb-based transition evidence.
- Hash retrieved APKs/images and retain the patch plus exact build command.

Do not interpret provider rejection as proof that WebAuthn routing is absent. Conversely, do not interpret API dispatch as proof that Google Password Manager approval or conditional UI works.

## Security boundary

Do not bypass provider allowlists, privileged-caller approval, relying-party origin validation, package signatures, verified boot, or device security. Use authorized test providers, test accounts, userdebug behavior, and documented configuration. Report external approval requirements as constraints.

## Output

Maintain a concise investigation record containing:

- hypothesis and expected distinguishing result;
- control/treatment configuration;
- pinned revisions and changed symbols;
- exact build and installation steps;
- observations and logs/artifact paths;
- conclusion with confidence and alternative explanations;
- next smallest experiment;
- GCP resources created and removed.
