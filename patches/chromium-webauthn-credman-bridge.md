# Common Credential Manager bridge: preparatory Chromium change

`chromium-webauthn-credman-bridge.patch` is the standalone, behavior-preserving
first step of the WebView passkey investigation. It extracts Credential Manager
events from Chrome's custom credential-selection bridge. It does **not** enable
WebView conditional mediation or change browser/provider authorization.

## Background and intent

The older `chromium-webview-browser-conditional.patch` combines this extraction
with new WebView BROWSER behavior. Those changes need separate review, rollout
decisions, and permission tests. The older prototype is retained unchanged;
the two patches are alternatives, not a stack to apply together.

This preparatory patch follows [Chromium CL 8381617](https://chromium-review.googlesource.com/c/chromium/src/+/8381617)
and incorporates the local file-by-file review and additional regression tests.
The aospman PR records the revised patch and evidence; it does not update the
Gerrit patchset or request upstream approval.

## Architectural boundary

- `WebauthnBrowserBridge` remains the bridge for Chrome's custom credential
  picker. Its name does not refer to `WebauthnMode.BROWSER`.
- `CredManHelper` forwards pending-request, UI-closed, password-selection, and
  cleanup events through `WebauthnCredManBridge` to the frame's existing native
  `WebAuthnCredManDelegate`.
- The new Java bridge has no native peer. Each JNI call looks up the delegate;
  the existing factory still requires an installed `WebAuthnClientAndroid`.
  Extracting this route does not make it available to every WebView host.
- APP requests act on behalf of the embedding Android app, with relying-party
  association. BROWSER requests act on behalf of the visited web origin and
  remain subject to browser permissions and credential-provider approval.

The reviewed helper event is named `onCredManUiClosed`, matching the existing
bridge/delegate terminology. Redundant `assumeNonNull` calls stay removed:
`getCredManBridge()` has a non-null contract and creates the Java bridge lazily.
That contract does not eliminate native frame/delegate validity checks.

The Chromium README now separates **Chrome credential-selection UI** from
**Credential Manager state and Autofill** within the integration section. Its
event diagram names the concrete delegate instead of implying a public callback
API for Android host apps.

The Chrome instrumentation mock also drops its obsolete
`cleanupCredManRequest()` override. Leaving it behind would prevent the Chrome
test APK from compiling after that method moves out of `WebauthnBrowserBridge`.

Runtime validation also exposed an existing race in the Chrome conditional
hybrid test: the response unblocks the test before completion callbacks run.
The same cleanup-count failure reproduced with the pristine control APK.
The test now uses the bounded cleanup wait already used by neighboring tests,
while still requiring exactly one cleanup call. Product behavior is unchanged.

## Source and reproduction

- Repository: <https://chromium.googlesource.com/chromium/src.git>
- Exact control/base: `e972dac6c18230a8cbae2a744593916a7da1d82c`.
- Treatment: that base plus `chromium-webauthn-credman-bridge.patch`.
- Applicability also checked on the affected-file snapshot of upstream main
  `e56f04e7cf5069c69db0ea27f75c49a24014fbac` (September 11): no conflicts.
  This does not substitute for building or running CQ on that newer main.
- Build/test scripts and configuration:
  [`artifacts/chromium-review-fixes-20260911/`](../artifacts/chromium-review-fixes-20260911/).

Apply only to a clean checkout at the documented base:

```sh
git apply --check /path/to/aospman/patches/chromium-webauthn-credman-bridge.patch
git apply /path/to/aospman/patches/chromium-webauthn-credman-bridge.patch
git diff --check
```

The recorded scripts use a disposable Linux `/work` checkout, Android x64 build
targets, and Chromium's API 34 / API 33 emulator configurations. Run the control
before applying the treatment. They are experiment scripts, not a command to
replace an existing developer checkout or local emulator.

## Regression coverage

The patch adds 17 test methods to existing registered test files:

| Layer | Added methods | Contract |
| --- | ---: | --- |
| CredMan helper (Robolectric) | 5 | No Chrome bridge: modal success/cancel, password forwarding, conditional cleanup, delayed prefetch after abort followed by a new request |
| Authenticator (Robolectric) | 2 | APP/BROWSER conditional availability and get/create capabilities remain false even when UVPAA is true |
| FIDO2 routing (Robolectric) | 1 | BROWSER conditional get remains rejected without dispatch to CredMan or Chrome UI |
| Native delegate | 3 | New state/callbacks after cleanup, single-use password callback, subsequent credentials-ready notification |
| Native delegate factory | 4 | Cross-document cleanup, same-document/uncommitted preservation, frame destruction and a new request |
| WebView instrumentation | 2 | JavaScript conditional availability and get/create capabilities remain false in APP/BROWSER |

Native navigation cases exercise observer notifications and frame lifetime in
unit tests, not a full page-navigation E2E. Java helper callbacks are mocks, not
evidence of credential-provider enrollment or end-to-end JNI routing.
The new WebView capability tests avoid a real GMS service connection on older
Android; the unit tests separately cover UVPAA returning true.
Validation also includes existing Chrome WebAuthn and touch-to-fill
instrumentation classes. Their backend/callback test doubles must not be
mistaken for a real credential-provider end-to-end passkey test.

## Validation result (2026-09-11)

| Suite | Control passed | Treatment passed |
| --- | ---: | ---: |
| Components WebAuthn Robolectric (SDK 29 / 36) | 162 | 178 |
| Native CredMan delegate/factory (API 34) | 6 | 13 |
| WebView WebAuthn (API 34, both process modes) | 12 | 16 |
| WebView WebAuthn (API 33, both process modes) | 12 | 16 |
| Chrome WebAuthn / touch-to-fill (API 34) | 125 | 125 |

All 17 added methods ran in their expected **31 variants** and passed. No
existing reported test disappeared. These main runs use `--num-retries=0`.
Both Chrome runs have two identical expected runtime skips and one pre-disabled
test excluded during discovery; none is counted as a pass.

The separate planned 20-run hybrid diagnostic reproduced the original cleanup
race in control (4 failures) and pre-fix treatment (2 failures). With the bounded
cleanup wait, **20/20 passed**. The failed historical reports are retained rather
than overwritten by the successful result.

The [comparison report](../artifacts/chromium-review-fixes-20260911/comparison.json)
checks individual test identities, expected variants, skip sets, phase completion,
and the stress run. Recheck the committed reports without a build:

```sh
node artifacts/chromium-review-fixes-20260911/compare-results.mjs
```

Commands, source pins, build settings, warnings, and cleanup are recorded in the
[investigation](../artifacts/chromium-review-fixes-20260911/investigation.md).
The builds use `treat_warnings_as_errors=false`; this is not Chromium CQ or a
full newer-main/CTS run. Large APKs and full logs are retained locally in the
investigation directory; the PR contains compact evidence and checksum manifests.

## Remaining work before enabling WebView conditional get

The feature work is intentionally separate: default-off flag and rollout,
permission guards and negative combinations, authorized BROWSER success paths,
real-provider Chrome conditional UI smoke, and end-to-end late-callback/navigation
coverage. Conditional create is not enabled by this patch. No provider allowlist,
origin validation, signature verification, or device security is bypassed.

Upstream submission also requires the contributor's own line-by-line review
under [Chromium's AI coding policy](https://chromium.googlesource.com/chromium/src/+/e972dac6c18230a8cbae2a744593916a7da1d82c/agents/ai_policy.md).
AI-assisted preparation and local test success are not substitutes for that
human review, upstream review, or CQ.
