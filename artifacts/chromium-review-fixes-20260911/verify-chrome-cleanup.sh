#!/usr/bin/env bash
set -euo pipefail

# Run after the fixed Chrome treatment build and its normal regression suite.
# This is a planned stress check, not a retry of a failed test.
export PATH="/work/src/third_party/depot_tools:${HOME}/depot_tools:${PATH}"
export DEPOT_TOOLS_UPDATE=0
readonly AOSPMAN_DIAGNOSTIC_RESULTS=/work/review-results/cleanup-diagnostic
mkdir -p "${AOSPMAN_DIAGNOSTIC_RESULTS}"
trap 'result=$?; printf "%s\n" "${result}" > "${AOSPMAN_DIAGNOSTIC_RESULTS}/fixed-exit-code.txt"; exit "${result}"' EXIT
cd /work/src
sha256sum out/review/apks/ChromePublicTest.apk \
  > "${AOSPMAN_DIAGNOSTIC_RESULTS}/fixed-apk-sha256.txt"
out/review/bin/run_chrome_public_test_apk \
  -f 'org.chromium.chrome.browser.webauth.Fido2CredentialRequestTest#testGetAssertion_conditionalUiHybrid_success' \
  --avd-config tools/android/avd/proto/android_34_google_apis_x64_local.textpb \
  --repeat=19 --num-retries=0 \
  --test-launcher-summary-output="${AOSPMAN_DIAGNOSTIC_RESULTS}/fixed.json" \
  > "${AOSPMAN_DIAGNOSTIC_RESULTS}/fixed.log" 2>&1
date -u '+%Y-%m-%dT%H:%M:%SZ' > "${AOSPMAN_DIAGNOSTIC_RESULTS}/fixed-finished-at.txt"
