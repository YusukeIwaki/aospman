#!/usr/bin/env bash
set -euo pipefail

# Usage: bash /work/build-and-test.sh control|treatment [--resume]
# Control is pristine CL parent; treatment applies the reviewed standalone patch.
readonly AOSPMAN_REVIEW_PHASE="${1:?Expected control or treatment}"
readonly AOSPMAN_REVIEW_BASE=e972dac6c18230a8cbae2a744593916a7da1d82c
readonly AOSPMAN_REVIEW_RESULTS="/work/review-results/${AOSPMAN_REVIEW_PHASE}"
readonly AOSPMAN_REVIEW_PATCH=/work/chromium-webauthn-credman-bridge.patch
case "${2:-}" in ''|--resume) ;; *) exit 1 ;; esac
if [[ "${2:-}" == --resume && "${AOSPMAN_REVIEW_PHASE}" != treatment ]]; then
  exit 1
fi
export PATH="/work/src/third_party/depot_tools:${HOME}/depot_tools:${PATH}"
export DEPOT_TOOLS_UPDATE=0
mkdir -p "${AOSPMAN_REVIEW_RESULTS}"
exec > >(tee -a "${AOSPMAN_REVIEW_RESULTS}/build-and-test.log") 2>&1
trap 'result=$?; printf "%s\n" "${result}" > "${AOSPMAN_REVIEW_RESULTS}/exit-code.txt"; exit "${result}"' EXIT

cd /work/src
test "$(git rev-parse HEAD)" = "${AOSPMAN_REVIEW_BASE}"
case "${AOSPMAN_REVIEW_PHASE}" in
  control)
    git diff --exit-code
    git diff --cached --exit-code
    ;;
  treatment)
    if [[ "${2:-}" == --resume ]]; then
      # Resume only after verifying that the updated standalone patch is applied.
      git apply --reverse --check "${AOSPMAN_REVIEW_PATCH}"
    else
      # A second invocation must not silently re-apply the patch.
      git diff --exit-code
      git diff --cached --exit-code
      git apply --check "${AOSPMAN_REVIEW_PATCH}"
      git apply "${AOSPMAN_REVIEW_PATCH}"
    fi
    git diff --check
    ;;
  *)
    printf 'Expected control or treatment, got %s\n' "${AOSPMAN_REVIEW_PHASE}" >&2
    exit 1
    ;;
esac

git status --short | tee "${AOSPMAN_REVIEW_RESULTS}/source-status.txt"
git -C third_party/depot_tools rev-parse HEAD | tee "${AOSPMAN_REVIEW_RESULTS}/depot-tools.txt"
date -u '+%Y-%m-%dT%H:%M:%SZ' | tee "${AOSPMAN_REVIEW_RESULTS}/started-at.txt"
cp chrome/VERSION "${AOSPMAN_REVIEW_RESULTS}/chromium-version.txt"
cp tools/android/avd/proto/android_{34,33}_google_apis_x64_local.textpb \
  "${AOSPMAN_REVIEW_RESULTS}/"
gn gen out/review --args='target_os="android" target_cpu="x64" is_debug=false is_component_build=false symbol_level=0 blink_symbol_level=0 v8_symbol_level=0 use_remoteexec=false treat_warnings_as_errors=false'
cp out/review/args.gn "${AOSPMAN_REVIEW_RESULTS}/args.gn"

autoninja -C out/review components_junit_tests -j 24
out/review/bin/run_components_junit_tests \
  -f 'org.chromium.components.webauthn.AuthenticatorImplTest.*:org.chromium.components.webauthn.Fido2CredentialRequestRobolectricTest.*:org.chromium.components.webauthn.cred_man.CredManHelperRobolectricTest.*' \
  --num-retries=0 \
  --test-launcher-summary-output="${AOSPMAN_REVIEW_RESULTS}/junit.json"

autoninja -C out/review components_unittests webview_instrumentation_test_apk -j 24
out/review/bin/run_components_unittests \
  -f 'WebAuthnCredManDelegateTest.*:WebAuthnCredManDelegateFactoryTest.*' \
  --avd-config tools/android/avd/proto/android_34_google_apis_x64_local.textpb \
  --num-retries=0 \
  --logcat-output-file="${AOSPMAN_REVIEW_RESULTS}/native-api34-logcat.txt" \
  --test-launcher-summary-output="${AOSPMAN_REVIEW_RESULTS}/native-api34.json"

for api_level in 34 33; do
  out/review/bin/run_webview_instrumentation_test_apk \
    -f 'WebAuthnTest#*' \
    --avd-config "tools/android/avd/proto/android_${api_level}_google_apis_x64_local.textpb" \
    --num-retries=0 \
    --logcat-output-file="${AOSPMAN_REVIEW_RESULTS}/webview-api${api_level}-logcat.txt" \
    --test-launcher-summary-output="${AOSPMAN_REVIEW_RESULTS}/webview-api${api_level}.json"
done

sha256sum out/review/apks/*.apk > "${AOSPMAN_REVIEW_RESULTS}/apk-sha256.txt"
# Preserve the control artifacts before the incremental treatment build replaces
# out/review. These are copied off the disposable VM before it is deleted.
mkdir -p "${AOSPMAN_REVIEW_RESULTS}/apks"
cp -a out/review/apks/*.apk "${AOSPMAN_REVIEW_RESULTS}/apks/"
date -u '+%Y-%m-%dT%H:%M:%SZ' | tee "${AOSPMAN_REVIEW_RESULTS}/finished-at.txt"
printf 'Completed %s.\n' "${AOSPMAN_REVIEW_PHASE}"
