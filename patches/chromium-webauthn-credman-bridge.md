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

This preparatory patch is published as
[Chromium CL 8381617 PS6](https://chromium-review.googlesource.com/c/chromium/src/+/8381617/6)
and incorporates the local file-by-file review, adversarial-review follow-up,
and additional regression tests. It remains **WIP** at the author's request
after the September 16 rebase. PS6 changes only the description; its source
tree and parent are identical to PS5. No upstream review, CQ or submit was
requested. The approved commit message is retained in
[`chromium-webauthn-credman-bridge-description.txt`](chromium-webauthn-credman-bridge-description.txt).

This aospman update exports the current patchset; it does not add another
Chromium source change. The new-base Android validation is still in progress.
The [export record](../artifacts/chromium-cl-8381617-ps6-pr-20260916/investigation.md)
records the source/description identity checks and the validation status at
PR preparation time. Full build logs and APKs are retained locally, not
included in this source-export PR.

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
bridge/delegate terminology. The September 14 follow-up removes the stateless
bridge's Provider, lazy cache, and test override. Its methods are static;
there is no nullable Java bridge instance to wrap in `assumeNonNull`.
Native frame/delegate validity checks remain in place.

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
requiring a count of one to be observed before the deadline. It does not prove
that a second call cannot happen later. Product behavior is unchanged.

## Source and reproduction

- Repository: <https://chromium.googlesource.com/chromium/src.git>
- Exact current parent/base: `1a4f4dba744599726855e4b1ccb7c3f328cd7b01`.
- Current published revision: PS6 `a991e498fa0fef2028edd9b8f2dacf8a54c32235`,
  equivalently the parent plus `chromium-webauthn-credman-bridge.patch`.
- Identical source tree in PS5 and PS6:
  `d2b4982a792fce53e0d09aabbb0c6d9761523fc0`.
- Current source-checked/published patch SHA-256:
  `9ada64624484a70dca42c29c7f2a91d36a23589a7254864b8ff0abf5edb8e6f3`.
  New-base validation is incomplete; see the current status below.
- Locally retained rebase, source checks and publication evidence:
  `artifacts/chromium-cl-8381617-rebase-20260916/`.
- Latest completed runtime comparison used parent
  `e972dac6c18230a8cbae2a744593916a7da1d82c`, control PS2
  `014e15b94d62ff8582db2d49b4a664b9355f63d3`, and treatment PS3
  `40a40d1a21ecb5f4db5125679a0793e6be84c38d`. PS4 only changed the description.
- Locally retained historical build/test scripts and configuration:
  `artifacts/chromium-cl-8381617-validation-20260914/`.

Apply only to a clean checkout at the documented base:

```sh
git apply --check /path/to/aospman/patches/chromium-webauthn-credman-bridge.patch
git apply /path/to/aospman/patches/chromium-webauthn-credman-bridge.patch
git diff --check
```

The current retry scripts are retained locally under
`artifacts/chromium-cl-8381617-ps5-retry-20260916/`. They use a disposable Linux
`/work` checkout, Android x64 targets, and Chromium's API 34 / API 33 emulator
configurations. This retry runs treatment first, then pristine pinned main,
checking source hashes before each phase. The September 14 scripts pin an
older base and are not a substitute for this new-base validation. These are
experiment scripts, not a command to replace an existing developer checkout
or local emulator.

## Regression coverage

The runtime-tested PS2 added 17 test methods to existing registered test files:

| Layer | Added methods | Contract |
| --- | ---: | --- |
| CredMan helper (Robolectric) | 5 | No Chrome bridge: modal success/cancel, password forwarding, conditional cleanup, delayed prefetch after abort followed by a new request |
| Authenticator (Robolectric) | 2 | APP/BROWSER conditional availability and get/create capabilities remain false even when UVPAA is true |
| FIDO2 routing (Robolectric) | 1 | BROWSER conditional get remains rejected without dispatch to CredMan or Chrome UI |
| Native delegate | 3 | New state/callbacks after cleanup, single-use password callback, subsequent credentials-ready notification |
| Native delegate factory | 4 | Cross-document cleanup, same-document/uncommitted preservation, frame destruction and a new request |
| WebView instrumentation | 2 | JavaScript conditional availability and get/create capabilities remain false in APP/BROWSER |

Native navigation cases exercise observer notifications and frame lifetime in
unit tests, not a full page-navigation E2E. In PS2, Java helper tests mocked the
new bridge, so those runs did not establish end-to-end JNI routing.
The new WebView capability tests avoid a real GMS service connection on older
Android; the unit tests separately cover UVPAA returning true.
Validation also includes existing Chrome WebAuthn and touch-to-fill
instrumentation classes. Their backend/callback test doubles must not be
mistaken for a real credential-provider end-to-end passkey test.

### September 14 adversarial-review follow-up (runtime-validated in PS3)

- R1: CredMan helper/routing tests now mock `WebauthnCredManBridge.Natives`
  through `WebauthnCredManBridgeJni.setInstanceForTesting`, leaving the real
  Java wrapper in the tested path. Eight new `WebAuthnCredManBridgeTest` native
  tests call a test-only Java helper, which calls the production Java/JNI entry
  points. They cover pending flags and the return callback, cleanup, UI-close
  success/failure, distinct Unicode username/password strings and child-frame
  selection, null/non-live frames, missing client, and late events sent through
  retained Java wrappers after native frame/WebContents destruction.
- R2: The misleading `GetLiveRenderFrameHost` helper is folded into delegate
  lookup; the factory retains the liveness/client checks. Request/document ID
  tracking is not introduced into this refactor: the base already looked up
  delegates per RFH on each notification. The new destruction tests do not
  simulate an old Credential Manager OutcomeReceiver after navigation that
  retains a live RFH. That reachability/lifetime question remains unresolved,
  and no same-RFH late-response safety claim is made.
- R3: Removed the unnecessary Provider/cache/native-peer ownership analogy.
  Static forwarding methods retain the existing generated JNI mock mechanism.

The new Java helper has its own test-only generated JNI headers and is directly
registered in the Android components test APK's dependencies. Validation
preparation added that direct APK dependency and //base:base_java for the
helper's callback type. The subsequent build and real-JNI runs passed; no
production behavior fix was necessary. The helper does not add test entry
points to the production Java API. The initial source-review decision record
is retained locally at
`artifacts/chromium-cl-8381617-review-fixes-20260914/investigation.md`;
the subsequent runtime results are summarized below.

## September 16 rebase (PS5, source checks only)

Upstream removed `SmallTest` from Robolectric tests and their unused AndroidX
test-runner dependency. Two conflicts were resolved in
`Fido2CredentialRequestRobolectricTest.java` and
`cred_man/CredManHelperRobolectricTest.java`, retaining all added `@Test`
methods, assertions and helpers while removing the obsolete annotations.
Other upstream AUTHORS/build/test-annotation changes merged automatically.

All 71 local source/format checks passed. The 89 Robolectric method names and
bodies across the three upstream-updated classes are preserved, as are the
eight real-JNI native tests; these counts are source checks, not new test runs.
Seventeen unaffected CL files, including production Java/C++, remain byte-for-byte
identical to PS4. The changed Java and GN files parse and pass formatting checks.
Gerrit reported PS5 `mergeable=true`, `work_in_progress=true` on September 16.

At the time of the rebase, Android builds, runtime tests, full upload presubmit
and CQ had not been rerun on the new base. Upstream changes include Fido2Api/features, the
Robolectric runner and JNI generation support, so historical runtime results
are not a substitute for new-base integration validation. The local rebase
record above retains the exact conflict, range diff, source-preservation and
publication checks.

## Current new-base validation (2026-09-16, in progress)

The earlier attempt was interrupted by Spot VM preemption. It retrieved 192
passing pristine-main tests, but no completed PS5 treatment result, so it did
not establish PS5 validation. That attempt remains recorded separately.

In the current retry, the exact PS5/PS6 source has built
`components_junit_tests` and passed all 178 expected WebAuthn Robolectric
test variants (SDK 29/36), once each with no retries. Native/WebView APKs
are still building as of 13:05 UTC. The native, WebView and Chrome runtime
suites, planned cleanup repetitions, mutation check, full presubmit and
same-run pristine-main comparison are pending. This is not an all-tests-pass
claim. No real-provider end-to-end test, CTS or Chromium CQ has been run.

The retry's incremental reports and APKs are retained locally at
`artifacts/chromium-cl-8381617-ps5-retry-20260916/`. Its Spot VM has an 8-hour
auto-delete limit; evidence verification and final cleanup/audit are pending.
The source-export PR remains Draft, independently of Gerrit's WIP status.

## Latest runtime validation before rebase (2026-09-14, PS2 versus PS3)

PS3 was rebuilt and tested on the same pinned parent `e972dac6c182`, toolchain,
GN configuration, and API 33/34 Android x64 AVDs as the PS2 control. The published
PS3 diff was byte-identical to the tested patch with SHA-256
`ba2ed5b91a0a2d3ba2e74415822e0c9b0ffc599e613d99832fee22a14a20b490`,
preserved in the September 14 artifacts. These runs do not cover PS5's new base.

| Suite | PS2 passed | PS3 passed |
| --- | ---: | ---: |
| Components WebAuthn Robolectric (SDK 29 / 36) | 178 | 178 |
| Native CredMan bridge/delegate/factory (API 34) | 13 | 21 |
| WebView WebAuthn (API 34, both process modes) | 16 | 16 |
| WebView WebAuthn (API 33, both process modes) | 16 | 16 |
| Chrome WebAuthn / touch-to-fill (API 34) | 125 | 125 |
| Total | 348 | 356 |

All eight new real Java/JNI/native tests executed and passed. No existing
reported test disappeared and no main-run test was retried. Chrome retained
the same two runtime skips and one pre-discovery exclusion. The September 13
WebView polling readability change is included in these successful runs.

The new routing test was also tested negatively: deliberately swapping native
username/password arguments caused one expected assertion FAILURE, not a
crash or timeout. Restoring the source produced 21/21 native passes and a
native APK byte-identical to the successful treatment APK. A fresh planned
20-run hybrid cleanup diagnostic passed 20/20 without retries. This does not
strengthen the bounded cleanup assertion into a guarantee against later calls.

Changed-line formatting and full upload presubmit completed with zero errors.
Two warnings concern an existing enum and framework exception literal, both
byte-identical to the parent; no suppression or unrelated rewrite was added.
Builds retain `treat_warnings_as_errors=false`. These are targeted synthetic
backend tests, not real-provider passkey/Autofill UI E2E, CTS, or Chromium CQ.
The same-live-RFH late OutcomeReceiver question above remains unresolved.

The locally retained runtime investigation at
`artifacts/chromium-cl-8381617-validation-20260914/investigation.md`
records commands, configuration, mutation evidence, hashes, limits, and WIP
publication checks. Its comparison and artifact verifiers passed 52 and 48
checks respectively. Recheck the retained reports without a new build:

```sh
node artifacts/chromium-cl-8381617-validation-20260914/compare-results.mjs
node artifacts/chromium-cl-8381617-validation-20260914/verify-artifacts.mjs
```

The disposable Spot VM and its boot disk were deleted after artifact retrieval;
the final GCP project audit is clean. Full APKs and logs are retained locally.

## Historical validation result (2026-09-11, pristine base versus PS2)

The results below refer to the tested patch with SHA-256
`d7338c55d543c8d80cab8b8864887ed9c3325ea3517dd0ec2ab0fbb44a3d70d8`,
preserved in aospman commit `2cfc7e43e1dc32426e9c4f8915ad3cb59e379762`
and Chromium CL 8381617 patchset 2.

These historical counts do not include the September 13 readability follow-up
(local record: `artifacts/chromium-test-review-followup-20260913/investigation.md`)
or September 14 real-JNI tests. Those changes were validated together in the
PS2-versus-PS3 experiment above. The historical control here is the pristine
parent, not PS2, and the historical failed stress reports remain preserved.

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
