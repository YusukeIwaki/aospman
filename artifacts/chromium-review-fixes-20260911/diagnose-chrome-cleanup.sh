#!/usr/bin/env bash
set -uo pipefail

# Reproduce a cleanup-count failure with the frozen control and treatment APKs.
# Twenty planned iterations, no retries and no stop-on-failure. Do not replace
# the main regression reports with these diagnostic runs.
export PATH="/work/src/third_party/depot_tools:${HOME}/depot_tools:${PATH}"
export DEPOT_TOOLS_UPDATE=0
readonly AOSPMAN_DIAGNOSTIC_RESULTS=/work/review-results/cleanup-diagnostic
mkdir -p "${AOSPMAN_DIAGNOSTIC_RESULTS}"
cd /work/src || exit 1
cp -a out/review/apks/ChromePublicTest.apk \
  "${AOSPMAN_DIAGNOSTIC_RESULTS}/treatment-before-cleanup-fix.apk"
for phase in control treatment; do
  if [[ "${phase}" == control ]]; then
    apk=/work/review-results/control/apks/ChromePublicTest.apk
  else
    apk="${AOSPMAN_DIAGNOSTIC_RESULTS}/treatment-before-cleanup-fix.apk"
  fi
  sha256sum "${apk}" > "${AOSPMAN_DIAGNOSTIC_RESULTS}/${phase}-apk-sha256.txt"
  out/review/bin/run_chrome_public_test_apk \
    --test-apk "${apk}" \
    -f 'org.chromium.chrome.browser.webauth.Fido2CredentialRequestTest#testGetAssertion_conditionalUiHybrid_success' \
    --avd-config tools/android/avd/proto/android_34_google_apis_x64_local.textpb \
    --repeat=19 --num-retries=0 \
    --test-launcher-summary-output="${AOSPMAN_DIAGNOSTIC_RESULTS}/${phase}.json" \
    > "${AOSPMAN_DIAGNOSTIC_RESULTS}/${phase}.log" 2>&1
  result=$?
  printf '%s\n' "${result}" > "${AOSPMAN_DIAGNOSTIC_RESULTS}/${phase}-exit-code.txt"
done
date -u '+%Y-%m-%dT%H:%M:%SZ' > "${AOSPMAN_DIAGNOSTIC_RESULTS}/finished-at.txt"
