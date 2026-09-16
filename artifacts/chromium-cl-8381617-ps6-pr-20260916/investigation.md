# Export Chromium CL 8381617 PS6 to an aospman pull request

- Date: 2026-09-16
- Status: source export verified; Android validation remains in progress
- Hypothesis: The aospman patch and description exactly reproduce published Chromium CL 8381617 PS6 without introducing further source changes.

## Question and scope

Export the current Chromium patchset to a new Draft aospman pull request.
The previous aospman PR #5 is already merged. Include the exact PS6 patch,
the user's approved description, updated scope/status notes and compact
identity-check evidence. Do not change Chromium source, Gerrit WIP, reviewers,
CQ or submit status. Exclude unrelated local Cuttlefish notes and large logs/APKs.

## Configuration

### Local and upstream revisions

- aospman base: `266c88d` (`origin/master`, merge of PR #5).
- New branch: `codex/credman-cl-8381617-ps6`.
- Upstream: https://chromium.googlesource.com/chromium/src.git
- Chromium parent: `1a4f4dba744599726855e4b1ccb7c3f328cd7b01`.
- PS5: `4f984322475c16188601bf0a6e01a758fe65d26b`.
- PS6: `a991e498fa0fef2028edd9b8f2dacf8a54c32235`.
- Identical PS5/PS6 tree: `d2b4982a792fce53e0d09aabbb0c6d9761523fc0`.
- Gerrit: https://chromium-review.googlesource.com/c/chromium/src/+/8381617/6

### Device, apps, and provider

No additional device, provider or app experiment is introduced by this export.
The ongoing Android validation uses Chromium 156.0.8061.0, SDK 29/36
Robolectric and API 33/34 x64 AVDs with synthetic credential-backend doubles.
Its full environment and eventual binary hashes belong to the separate local
record `artifacts/chromium-cl-8381617-ps5-retry-20260916/investigation.md`.

### Relying party

No real RP/account is accessed by the export. The separate tests use upstream
synthetic test data; no credential-provider approval or trust checks are bypassed.

## Experiment design

| Case | Control or treatment | Expected falsifier | Result |
| --- | --- | --- | --- |
| Source patch | Published PS6 diff vs aospman patch | Any byte mismatch | Identical |
| Description | Published PS6 message vs exported text | Any byte mismatch | Identical |
| Validation input | PS5 tree/frozen patch vs PS6 | Source drift | Identical |
| Review status | Fresh Gerrit response | Not PS6, closed, or not WIP | PS6, NEW, WIP |

## Reproduction

```sh
# Requires a Chromium checkout containing the pinned PS5/PS6 commits.
node artifacts/chromium-cl-8381617-ps6-pr-20260916/verify-export.mjs /path/to/chromium/src

# Apply the source-only patch in a separate clean checkout at the pinned parent.
git apply --check /path/to/aospman/patches/chromium-webauthn-credman-bridge.patch
git apply /path/to/aospman/patches/chromium-webauthn-credman-bridge.patch
git diff --check
```

## Observations and evidence

At 2026-09-16 13:06:58 UTC, all nine source-export checks passed.
The verifier reads local Git objects and performs a public, read-only Gerrit
GET. It makes no source, review, account or cloud changes. The report is
[`export-verification.json`](export-verification.json).

The source patch includes the native JNI test coverage and static bridge
follow-up, the readable WebView polling helper, and the September 16 main
rebase. PS6 itself changes only the description relative to PS5. The exported
description preserves the user's text, with only line wrapping and the
existing title/Bug/Change-Id included.

## Result and causal assessment

The source-export hypothesis is supported: the committed patch is exactly the
published PS6 source diff, and the description is exactly its commit message.
This does not establish Android runtime correctness or readiness to merge.

## Remaining uncertainty and next experiment

The new-base Android retry remains in progress. At PR preparation time,
178/178 treatment Robolectric variants passed once without retries; native,
WebView and Chrome APK/runtime work, the same-run pristine-main comparison,
cleanup repetitions, mutation test and full presubmit remain incomplete.
The earlier preempted attempt is not counted as completed PS5 validation.
Historical PS3 results are labelled separately in the patch notes.

Continue the existing validation; do not remove Draft/WIP or claim an
all-tests-pass result on the strength of this source-export check. The
same-live-RenderFrameHost late OutcomeReceiver limitation, real-provider
end-to-end behavior and Chromium CQ remain outside these identity checks.

## Artifacts and hashes

- [`../../patches/chromium-webauthn-credman-bridge.patch`](../../patches/chromium-webauthn-credman-bridge.patch)
  SHA-256: `9ada64624484a70dca42c29c7f2a91d36a23589a7254864b8ff0abf5edb8e6f3`.
- [`../../patches/chromium-webauthn-credman-bridge-description.txt`](../../patches/chromium-webauthn-credman-bridge-description.txt)
  SHA-256: `b767ec0c97fe53aba0d1932c5ea2ffffee332b6a3f420393867cafab189677be`.
- [`verify-export.mjs`](verify-export.mjs) and
  [`export-verification.json`](export-verification.json) reproduce the identity
  checks. The live Gerrit-state check intentionally fails if the current
  patchset or WIP status later changes.
- Full runtime reports, build logs and APKs remain local. None is implied to
  be published merely by mentioning its local path in the patch notes.

## Tests and warnings

All nine export checks passed, with no mismatch. These are not Android test
results. The separate 178-pass Robolectric report was checked against the
predeclared exact test identities, statuses and single-run counts. Remaining
Android tests, warnings and cleanup results must be reported by that run.

## GCP resources and cleanup

No resources were created or modified for the PR/export. The previously
authorized validation continues on `aospman-credman-ps5-retry-0916` in project
`aospman`, zone `asia-northeast1-b`: n2-highcpu-32 Spot, one auto-deleting
500GB boot disk, 8-hour maximum lifetime ending about 2026-09-16 20:17:33 UTC.
Incremental evidence retrieval is active. Final deletion and audit for that
separate validation are still pending; this record does not claim cleanup.
