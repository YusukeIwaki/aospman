# Chromium CredMan bridge review fixes and regression validation for aospman PR

- Date: 2026-09-11
- Status: complete — targeted validation passed; evidence retained; GCP audit clean
- Hypothesis: The reviewed naming and documentation changes preserve CredMan routing, and the additional Java/native/WebView regression tests pass on the CL1 source.

## Question and scope

Apply the previously deferred R1–R5 review fixes, run the additional 17 tests and
existing regressions, and create an aospman Pull Request only after validation.
This is the preparatory CredMan bridge extraction (CL 8381617), not the later
WebView BROWSER conditional-get feature. The older combined prototype patch is
preserved unchanged. No Gerrit patchset update or reviewer message is authorized
by this aospman PR task.

Stopping condition: all targeted final suites and all added variants pass with
only the documented baseline skips, the bounded hybrid stress check passes,
artifacts are copied and verified, and the disposable cloud resources are gone.

## Configuration

### Local and upstream revisions

- aospman: base `98d1b0f`, branch `codex/credman-review-fixes`.
- Chromium repository: https://chromium.googlesource.com/chromium/src.git
- Chromium build/control pin: `e972dac6c18230a8cbae2a744593916a7da1d82c`.
- Local CL1 commit: `afa99124011abc865f390cc1710042ae76926882` in
  `/Users/yusuke-iwaki/src/chromium-passkey-upload`, plus the reviewed changes.
- Observed upstream HEAD on 2026-09-11:
  `e56f04e7cf5069c69db0ea27f75c49a24014fbac`. The build intentionally uses the
  exact existing CL parent rather than silently changing its dependency graph.
- Chromium version at the build pin: `155.0.8051.0` (`chrome/VERSION`).
- Build depot_tools revision: `1e5e3539fa466cb2e2e203f9eff5886bb581145d`.
- Build host: Ubuntu 22.04.5 LTS x86_64, image
  `ubuntu-os-cloud/ubuntu-2204-jammy-v20260906`, kernel `6.8.0-1066-gcp`.
- Gerrit: https://chromium-review.googlesource.com/c/chromium/src/+/8381617
- Standalone treatment patch: `patches/chromium-webauthn-credman-bridge.patch`.

### Device, apps, and provider

Controlled environment: remote Linux x64 build and upstream Chromium
API 34 / API 33 x64 AVD configurations. Actual fingerprints and test package
versions are recorded below and in each phase's `apk-metadata.txt`.
No real user accounts or credentials are involved. Local API 36 arm64 emulator
and its provider remain untouched.

- Emulator CIPD instance: `QgDCxG9OzoQx04LpwnENgTz3gby5-Kyx6Rsv5yl91p4C`
  (36.4.9 Stable).
- API 34 `_local` AVD: `TfDrwbIlj07Hc-0odvpYj7GhvhXyAEkY6uhOr34fjD4C`;
  system image `TIwWQNogvpRgkhjpGkQnJrpAToU2WL10bk9hJ9WNkdAC`
  (r14, UE1A.230829.050), lavapipe GPU.
- API 33 `_local` AVD: `Vsp8X1DdSLJmQFDto4WkH92p8Zsvgr1Oz1TeQOS2FtkC`;
  system image `4c9il1xIZwca_xJABnQ1KstiU1kFqzOonoQGdweA77cC`
  (r15, TE1A.220922.034), swangle_indirect GPU.
- These upstream test AVDs document patched GMS Core 25.07.33. They are test
  fixtures, not evidence of production provider acceptance. WebAuthnTest also
  overrides the version reported to Chromium to 240700000 and intercepts the
  relevant FIDO2 request; no real credentials are enrolled or retrieved.
- Both AVDs booted successfully; the separate boot-check instances were stopped.
  Actual fingerprints, captured before test execution:
  - API 34: `google/sdk_gphone64_x86_64/emu64xa:14/UE1A.230829.050/12077443:userdebug/dev-keys`.
  - API 33: `google/sdk_gphone_x86_64/emu64xa:13/TE1A.220922.034/10940250:userdebug/dev-keys`.
  - Both report ABI `x86_64` and updated GMS Core `250733032` / `25.07.33`.
  - The system-selected stock WebView is 113.0.5672.136 on API 34 and
    103.0.5060.71 on API 33. It is **not** the code under test: the
    WebViewInstrumentation APK embeds the newly compiled Aw implementation.
  - Evidence: `api34-environment.txt`, `api33-environment.txt`, and boot logs.
- The Chrome instrumentation classes use the upstream `applyFidoOverride()`
  test helper to configure the test APK's signing fingerprint for the GMS FIDO2
  fixture. That isolated test-only configuration must not be represented as
  production Credential Manager / Google Password Manager browser approval.
  Credential results and browser callbacks in these tests are synthetic.
- APK identity is identical across phases: Chrome test app
  `org.chromium.chrome.tests` version `155.0.8051.0` / `805100008`;
  embedded WebView app `org.chromium.android_webview.shell`, instrumentation
  `org.chromium.android_webview.test`, and native tests `org.chromium.native_test`
  use version code 1 / `Developer Build`. All saved APKs use test certificate
  SHA-256 `32a2fc74d731105859e5a85df16d95f102d85b22099b8064c5d8915c61dad1e0`.
  Manifest permissions and support APK identities are in `control/apk-metadata.txt`
  and `treatment/apk-metadata.txt`. No manual/real-provider UI smoke is claimed.

### Relying party

The upstream WebAuthnTest uses its local TestWebServer (localhost / 127.0.0.1)
and `a.test` with an
intentionally mismatched TLS certificate for the SSL-error negative test.
Chrome instrumentation uses `subdomain.example.test` on its local test server.
Robolectric/native unit tests use mocks. These are not provider-approval or
real-RP passkey enrollment experiments.

## Experiment design

| Case | Control or treatment | Expected falsifier | Result |
| --- | --- | --- | --- |
| Existing Java WebAuthn tests | control and treatment | Regression in existing expectations | Control 162/162 pass; treatment 178/178 including additions, no retries |
| New Java cases | treatment | Missing CredMan callbacks, broken cancellation/retry, changed capabilities | All 16 SDK variants of 8 added methods passed in the initial treatment run |
| Native delegate/factory tests | control and treatment | Stale state/callbacks after cleanup, navigation or frame destruction | Control 6/6; treatment 13/13 pass |
| WebAuthnTest, API 34 | control and treatment | APP/NONE regression or unexpected WebView conditional support | Control 12/12; treatment 16/16 single-/multiprocess variants pass |
| WebAuthnTest, API 33 | control and treatment | Regression in unsupported/legacy paths | Control 12/12; treatment 16/16 single-/multiprocess variants pass |
| Chrome WebAuthn and touch-to-fill instrumentation, API 34 | control and treatment | Broken Chrome test consumer, conditional routing or credential-entry UI regression | Final control and treatment: 125 passed, 2 skipped; 1 pre-disabled test excluded in each; historical cleanup race documented below |

## Reproduction

```sh
# VM profile/disk exception explicitly approved by the user.
AOSPMAN_ENABLE_NESTED_VIRT=1 .agents/skills/manage-aosp-spot-build/scripts/spot-vm.sh create constrained aospman-credman-review-20260911 8 500
.agents/skills/manage-aosp-spot-build/scripts/spot-vm.sh bootstrap aospman-credman-review-20260911
# On that VM, scripts stored alongside this record:
bash /work/prepare-checkout.sh
bash /work/prepare-swap.sh
bash /work/prepare-avds.sh # optional prefetch, may overlap compilation
bash /work/build-and-test.sh control
bash /work/build-and-test-chrome.sh control
bash /work/record-apks.sh control
bash /work/build-and-test.sh treatment
bash /work/build-and-test-chrome.sh treatment
bash /work/record-apks.sh treatment
```

For a long remote run, `run-all.sh` executes the same phases sequentially.
Launch it with `nohup` and file redirection as documented in that script, so
the build does not depend on a continuously connected SSH output stream.

## Observations and evidence

- Initial cloud audit: no instances, disks, static addresses, snapshots or images.
- Standard 90/96 vCPU profiles fail current quotas. The user explicitly approved
  Spot n2-highcpu-32 / 500GB / at most 8 hours and immediate post-copy cleanup.
- Applied review items R1–R5: common event naming, precise password-forwarding
  comment, APP/BROWSER definitions, Integration subheadings, corrected event path.
- Retained the removal of redundant `assumeNonNull` calls (N1).
- Also aligned the new Java bridge's class comment with its per-frame native
  delegate destination.
- Existing 17 test additions remain in scope; no new WebView feature was enabled.
- Bootstrap, source/dependency checkout, build dependencies, and hooks succeeded.
  `/dev/kvm` is available for the emulator tests. Control build started.
- Initial patch SHA-256 was checked locally and after transfer to the VM:
  `13dcdba14ff1f3bcff21e843322e0152292195ec0d23c11d7bb320fe84564769`.
- During source review, the added WebView capability tests were found to reach
  the real GMS UVPAA call on pre-CredMan Android. They now override
  `Fido2ApiCallHelper.arePlayServicesAvailable()` to false within those cases,
  keeping them independent of GMS service state. API 34 still exercises the
  ordinary CredMan availability branch. Separate Java unit cases cover UVPAA
  true with conditional capabilities false. Product behavior is unchanged.
- Control Java build completed; the three selected WebAuthn classes passed
  162/162 variants at 01:35:54 UTC, `--num-retries=0`. Native/instrumentation
  build started next. Report: `control/junit.json`.
- Upstream compatibility check at `e56f04e7cf5069c69db0ea27f75c49a24014fbac`:
  all affected existing source/test/README files have the same blobs as the CL
  parent; only AUTHORS differs (three unrelated additions elsewhere). Exported
  the 16 existing affected paths into a temporary directory and ran full-patch
  `git apply --check`: pass. The two new bridge files remain absent upstream.
  An earlier probe ran before the export finished and reported missing files;
  the completed-export check is the valid result. The temporary copy was then
  removed. This is an applicability check, not a build of that newer main.
- The wider Chrome consumer search found a stale `@Override cleanupCredManRequest()`
  in `chrome/android/javatests/src/org/chromium/chrome/browser/webauth/WebauthnTestUtils.java`.
  The superclass method is removed by
  this refactor, so keeping the no-op override would break Chrome test APK
  compilation. Removed that obsolete override (three lines).
- Added `chrome_public_test_apk` validation to both phases, selecting Chrome's
  `webauth.AuthenticatorImplTest`, `webauth.Fido2CredentialRequestTest`, and
  `touch_to_fill.TouchToFillPasswordManagerIntegrationTest`. These existing
  tests exercise Android runtime and Chrome UI, but their FIDO2/backend and
  bridge callbacks use upstream test doubles; they do not prove real provider
  acceptance or end-to-end CredMan passkey completion.
- Repeated the upstream applicability check after adding the Chrome mock fix:
  full 19-file patch passes on the 17 existing affected paths from `e56f04e7...`;
  the temporary source snapshot was removed afterwards.
- During the control Blink compile, RAM usage reached about 25GiB of 31GiB.
  Added 16GiB of ephemeral swap inside the existing 500GB boot disk to reduce
  OOM risk. No extra VM/disk/cache or persistent fstab change is used. Both
  phases use the same physical memory configuration; treatment also has this
  swap available. No OOM or build failure had occurred when it was added.
- `run-remaining.sh` queues the remaining Chrome-control, treatment, and
  Chrome-treatment phases after the already-running pristine control exits
  successfully. It uses the same checkout sequentially and stops on the first
  failure; it does not submit any PR or create any additional cloud resources.
- `compare-results.mjs` checks successful phase completion, compares individual
  test names (not just totals), rejects missing/repeated/non-success results,
  and requires all 17 added methods in their intended suites. Its initial run
  correctly reported missing results before the remaining suites finished.
- The new WebView capability helper additionally asserts the requested mode was
  applied before checking JavaScript results. This makes the negative assertion
  explicitly about APP/BROWSER, not an accidentally unchanged setting. Rechecked
  the final patch against both the pristine build checkout and the affected-file
  snapshot of `e56f04e7...`: both pass; the temporary snapshot was removed.
- Replaced `<string>` with `<string_view>` in `webauthn_client_android.h`:
  removing the CredMan password method leaves only `std::u16string_view` in
  that interface. Its pinned formatter check and full-patch applicability checks
  on both revisions pass. The successful native/WebView and Chrome builds
  validate the updated header and its consumers.
- Infrastructure interruption: the initial pristine-control build stopped at
  03:19 UTC with exit code 243, consistent with SIGPIPE propagated by the
  launcher. Its log ends during compilation (43,239 completed steps), without
  a compiler error. The remaining-phase queue then exited 1 without applying
  treatment. Kernel logs showed no OOM, and the VM had not rebooted.
  GCP management API calls also intermittently failed with `SSLEOFError`.
  Retrieved the interrupted log, saved its exit code and earlier passing Java
  report, and resumed the pristine control with its incremental build outputs
  using detached `run-all.sh`. No source/test expectation changed in response
  to this interruption. Subsequent SSH access uses the same verified host key
  and identity reported by `gcloud compute ssh --dry-run`; TLS and host-key
  validation remain enabled.
- Detached retry started at 03:54:40 UTC. The Java suite again passed all 162
  variants with no test retries, then the native/WebView build resumed with
  approximately 10,657 remaining steps. The completed outputs were reused.
  Closed the two stale local SSH client sessions from the interrupted run;
  the detached remote pipeline is independent of those clients.
- Resumed native/WebView build completed at 04:23 UTC. API 34 control results:
  native delegate/factory 6/6 pass; WebAuthnTest 12/12 pass across single-process
  and multiprocess variants. Reports were retrieved before starting treatment.
- The native test APK is generated as
  `out/review/components_unittests_apk/components_unittests-debug.apk`, outside
  `out/review/apks`. Artifact preservation now explicitly includes it and
  produces a portable checksum list relative to each phase's saved APK folder.
- API 33 WebAuthnTest control also passed 12/12 variants. The main control phase
  finished at 04:26:21 UTC with exit code 0. Chrome control build started next.
- Chrome control build succeeded. Its API 34 run reported 127 variants:
  125 successful and two skipped, with no failures. One additional pre-disabled
  test was excluded during discovery. Source-verified conditions at the pin:
  - `TouchToFillPasswordManagerIntegrationTest.testConsumesGenericMotionEventsToPreventMouseClicksThroughSheet`:
    `@DisableIf.Build(sdk_equals = 34)` at lines 146–149 of
    `chrome/browser/touch_to_fill/password_manager/android/javatests/src/org/chromium/chrome/browser/touch_to_fill/TouchToFillPasswordManagerIntegrationTest.java`.
  - `Fido2CredentialRequestTest.testMakeCredential_doesNotSetPaymentOptionsWhenNonPaymentCredential`:
    `Assume.assumeFalse(BuildConfig.ENABLE_ASSERTS)` at line 1770. This build has
    Java assertions enabled, despite `is_debug=false`.
  - `TouchToFillPasswordManagerIntegrationTest.testShowsAfterPreviousSheetDismissal`:
    already marked `@DisabledTest(message = "crbug.com/515482528")` at line 317.
  These are not successful tests. The comparison script permits only the two
  known runtime skips and requires identical skip sets between control and
  treatment; any unexpected skip, failure, retry, or missing test still fails.
- Initial treatment Java result: all 178 variants passed. Native compilation
  then found a type error in the added password-filling test: UTF-16 literals
  could not implicitly convert to `Matcher<const std::u16string&>`.
  Replaced the two literal expectations with explicit `testing::Eq` matchers,
  preserving the required username/password equality. No product code or
  assertion was relaxed. Saved the failed build log and initial Java report,
  applied `native-matcher-fix.patch` to the disposable checkout, regenerated
  the standalone patch, and started detached `resume-treatment.sh` at
  05:01:13 UTC. The corrected native test compiled successfully. Java passed
  178/178, native passed 13/13, and WebView passed 16/16 on each API level.
  Main treatment finished at 05:05:51 UTC with exit code 0.
- Chrome treatment built successfully, but the first instrumentation run failed
  `Fido2CredentialRequestTest.testGetAssertion_conditionalUiHybrid_success`:
  expected cleanup count 1, observed 0. Its preceding authentication success and
  response-content assertions passed. The report has 124 successes, two expected
  skips, and this one failure. This result is preserved, not counted as a pass.
  `WebauthnRequestCallback.onComplete()` delivers the response before running
  completion callbacks, while `AuthenticatorCallback.blockUntilCalled()` only
  waits for the response. The assertion can therefore race cleanup. Nearby tests
  already poll for cleanup. `diagnose-chrome-cleanup.sh` runs a planned 20
  iterations each with frozen control and treatment APKs, without retries, to
  distinguish an existing timing issue from a refactor regression.
- The planned 20-iteration diagnostic reproduced exactly the cleanup-count
  assertion on both frozen APKs: pristine control 16 successes / 4 failures;
  pre-fix treatment 18 successes / 2 failures. No crashes, timeouts, or skips.
  The existing response-before-completion ordering and these control failures
  identify a pre-existing test synchronization defect, not a missing passkey
  response. Added bounded `CriteriaHelper.pollInstrumentationThread()` for
  cleanup count **exactly 1**, as used by nearby conditional UI tests; no product
  behavior or expected value was changed. The final 20-file patch was
  rebuilt and all main regression suites rerun. A further planned 20-iteration
  fixed-case run was checked. Failed reports and the pre-fix APK remain preserved.
- The final patch also passes `git apply --check` on an exported affected-file
  snapshot of `e56f04e7...`: 18 existing paths plus two new files. The temporary
  snapshot was removed. The newly changed Chrome test passes the pinned Java
  formatter's complete-file dry-run.
- Final main treatment rerun completed at 05:26:25 UTC; the Chrome rerun finished
  at 05:31:55 UTC with 125 successes and the same two expected skips, no failures
  or test retries. The independent synchronization check passed all 20 iterations
  and finished at 05:34:35 UTC. Final pipeline, including artifact metadata,
  finished at 05:34:52 UTC with exit code 0.

## Result and causal assessment

The targeted behavior-preservation hypothesis is supported by the final main
suites: control has 317 successful variants; treatment has 348. Both have the
same two expected runtime skips and one discovery-disabled Chrome test.
All 17 added methods executed their expected 31 variants successfully. The
comparison checks test identities, so this is not just a comparison of totals.
The synchronized hybrid test additionally passed 20/20 planned iterations.
The initial treatment native compile error was fixed without changing the
expectation; the Chrome failure was reproduced in pristine control and fixed
as a test synchronization defect. Neither failure was silently retried away.
The prior September 10 result predates these review fixes and added tests and
is not counted as this run. These targeted results support the extraction's
contracts, not production provider acceptance or WebView conditional enablement.

## Remaining uncertainty and next experiment

Flag control/treatment, missing privileged permissions, actual BROWSER
conditional success, provider trust, and Chrome UI smoke are separate from this
behavior-preserving extraction. The added Chrome instrumentation uses test
doubles; real-provider Chrome conditional completion remains separate. This run must not be reported as completion of
all requirements for shipping WebView conditional mediation.

## Artifacts and hashes

Scripts and GCP preflight evidence are in this directory. Current treatment
patch (20 files, 767 insertions / 317 deletions) SHA-256:
`d7338c55d543c8d80cab8b8864887ed9c3325ea3517dd0ec2ab0fbb44a3d70d8`.
All nine control APKs and all nine final treatment APKs were copied locally and
verified against `control/apk-sha256.txt` and `treatment/apk-sha256.txt` with
`shasum -a 256 -c`. The frozen pre-fix Chrome APK also matches its diagnostic
checksum. Configurations (GN args, depot_tools, Chromium version, AVD definitions,
and APK package/signing metadata) match between phases.

- Machine-readable verdict: `comparison.json`; regenerate with
  `node artifacts/chromium-review-fixes-20260911/compare-results.mjs` from aospman.
- Final and historical summaries: `control/*.json`, `treatment/*.json`,
  `cleanup-diagnostic/*.json`; short launcher evidence: `runner-excerpts.txt`.
- Binary manifests: each phase's `apk-sha256.txt`; full-log/report hashes:
  `evidence-sha256.txt` (paths relative to this directory).
- Full APKs, build logs, raw logcat, and per-test HTML/logs are retained locally
  under `control/`, `treatment/`, `cleanup-diagnostic/`, and `all-test-results/`
  in `/Users/yusuke-iwaki/src/github/YusukeIwaki/aospman/artifacts/chromium-review-fixes-20260911/`.
  The GitHub PR includes compact reports, scripts, metadata, and hashes, **not**
  these approximately 4 GB of large local artifacts.
- Existing combined prototype remains unchanged: SHA-256
  `d6c264ac07a3d80d2d2dba065ba36cc06bad64cb4c1d3eda714aeb9cad815907`.
- This aospman PR prepares a reproducible patch and evidence. It does not claim
  Gerrit approval, a CQ pass, newer-main execution, or completion of the separate
  WebView feature-launch/permission/provider work.

## Tests and warnings

- Local patch reverse-application check and `git diff --check` pass.
- Java naming/comment edits formatted with the pinned Chromium formatter.
- Build/test shell scripts pass `bash -n`.
- Complete reviewed Java helper/bridge files pass pinned google-java-format
  dry-run; the new native bridge and both changed native test files pass pinned
  clang-format dry-run with `--Werror`.
- Preparation warning: Ubuntu's Git 2.34.1 is older than depot_tools' recommended
  2.46.0; checkout and hooks nevertheless completed successfully.
- First control invocation stopped before GN/build: the Chromium-pinned
  `third_party/depot_tools` runtime had not been bootstrapped
  (`python3_bin_reldir.txt not found`). Added its documented `ensure_bootstrap`
  step to preparation. No product or test expectations changed.
- The pinned bootstrap script must be invoked by absolute path; its relative
  invocation failed to find CIPD digests. With the absolute path and explicit
  runtime-file check, initialization succeeded. GN then generated 67,491 targets
  from 4,707 files and compilation started at 01:16 UTC.
- Chrome's API 34 harness reports four unknown newer-SDK permissions while
  installing the SDK 37 test APK: `ACCESS_HID`, `ACCESS_LOCAL_NETWORK`,
  `FOREGROUND_SERVICE_SHORT_SERVICE`, and `POST_PROMOTED_NOTIFICATIONS`. These
  warnings occur in both phases and do not prevent the selected suites passing.
- Full-file Java formatter checks also found two pre-existing differences in
  untouched lines: the `RequestMetrics.Builder` wrap in `Fido2CredentialRequest`
  and a long existing method declaration in its Robolectric test. Both are
  identical in the pristine CL parent and were left unchanged to avoid unrelated
  formatting churn. All other changed Java files pass full-file dry-run.

## GCP resources and cleanup

- Created and removed managed VM: `aospman-credman-review-20260911`, project `aospman`,
  `asia-northeast1-b`, Spot `n2-highcpu-32`, 500GB auto-delete pd-balanced boot disk.
- Nested virtualization enabled for the test emulators; no service account or scopes.
- Creation time: 2026-09-11 00:51:40 UTC.
- Verified `maxRunDuration.seconds=28800`, termination action DELETE;
  independent maximum lifetime deadline approximately 08:51:40 UTC (17:51 JST).
- Cleanup executed after evidence retrieval and binary checksum verification:
  `.agents/skills/manage-aosp-spot-build/scripts/spot-vm.sh delete aospman-credman-review-20260911`.
- The VM and its 500GB boot disk were deleted. The source checkout, intermediates,
  test AVDs, and temporary swap were not retained; patches, APKs, and evidence were.
  No additional disk, snapshot, static IP, bucket, service account, or cache was
  created. The final project audit completed before 05:40:34 UTC and lists no
  instances, disks, reserved addresses, snapshots, or custom images.
  Evidence: `gcp-delete.txt`, `final-gcp-audit.txt`, `vm-before-cleanup.yaml`.
