#!/usr/bin/env bash
set -euo pipefail

# Run after the corresponding build-and-test.sh phase and before applying a new
# treatment. Both scripts share out/review and must not run concurrently.
readonly AOSPMAN_REVIEW_PHASE="${1:?Expected control or treatment}"
case "${AOSPMAN_REVIEW_PHASE}" in control|treatment) ;; *) exit 1 ;; esac
readonly AOSPMAN_REVIEW_RESULTS="/work/review-results/${AOSPMAN_REVIEW_PHASE}"
export PATH="/work/src/third_party/depot_tools:${HOME}/depot_tools:${PATH}"
export DEPOT_TOOLS_UPDATE=0
exec > >(tee -a "${AOSPMAN_REVIEW_RESULTS}/chrome-build-and-test.log") 2>&1
trap 'result=$?; printf "%s\n" "${result}" > "${AOSPMAN_REVIEW_RESULTS}/chrome-exit-code.txt"; exit "${result}"' EXIT

cd /work/src
test "$(git rev-parse HEAD)" = e972dac6c18230a8cbae2a744593916a7da1d82c
if [[ "${AOSPMAN_REVIEW_PHASE}" == control ]]; then
  git diff --exit-code
  git diff --cached --exit-code
else
  git apply --reverse --check /work/chromium-webauthn-credman-bridge.patch
fi

autoninja -C out/review chrome_public_test_apk -j 24
out/review/bin/run_chrome_public_test_apk \
  -f 'org.chromium.chrome.browser.webauth.AuthenticatorImplTest#*:org.chromium.chrome.browser.webauth.Fido2CredentialRequestTest#*:org.chromium.chrome.browser.touch_to_fill.TouchToFillPasswordManagerIntegrationTest#*' \
  --avd-config tools/android/avd/proto/android_34_google_apis_x64_local.textpb \
  --num-retries=0 \
  --logcat-output-file="${AOSPMAN_REVIEW_RESULTS}/chrome-api34-logcat.txt" \
  --test-launcher-summary-output="${AOSPMAN_REVIEW_RESULTS}/chrome-api34.json"

mkdir -p "${AOSPMAN_REVIEW_RESULTS}/apks"
cp -a out/review/apks/*.apk "${AOSPMAN_REVIEW_RESULTS}/apks/"
sha256sum out/review/apks/*.apk > "${AOSPMAN_REVIEW_RESULTS}/apk-sha256.txt"
date -u '+%Y-%m-%dT%H:%M:%SZ' | tee "${AOSPMAN_REVIEW_RESULTS}/chrome-finished-at.txt"
