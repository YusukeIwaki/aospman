#!/usr/bin/env bash
set -euo pipefail

# Run after a completed control or treatment phase has preserved its APKs.
readonly AOSPMAN_REVIEW_PHASE="${1:?Expected control or treatment}"
case "${AOSPMAN_REVIEW_PHASE}" in control|treatment) ;; *) exit 1 ;; esac
readonly AOSPMAN_REVIEW_RESULTS="/work/review-results/${AOSPMAN_REVIEW_PHASE}"
readonly AOSPMAN_REVIEW_BUILD_TOOLS=/work/src/third_party/android_sdk/public/build-tools/37.0.0
# The native unit-test APK is generated outside out/review/apks.
cp -a /work/src/out/review/components_unittests_apk/components_unittests-debug.apk \
  "${AOSPMAN_REVIEW_RESULTS}/apks/"
(cd "${AOSPMAN_REVIEW_RESULTS}/apks" && sha256sum ./*.apk) \
  > "${AOSPMAN_REVIEW_RESULTS}/apk-sha256.txt"
# Keep per-test logcats and HTML reports as well as the launcher summaries.
mkdir -p "${AOSPMAN_REVIEW_RESULTS}/test-results"
for result_dir in /work/src/out/review/TEST_RESULTS_*; do
  if [[ -d "${result_dir}" && "${result_dir}" -nt "${AOSPMAN_REVIEW_RESULTS}/started-at.txt" ]]; then
    cp -a "${result_dir}" "${AOSPMAN_REVIEW_RESULTS}/test-results/"
  fi
done
exec > >(tee "${AOSPMAN_REVIEW_RESULTS}/apk-metadata.txt") 2>&1

for apk in "${AOSPMAN_REVIEW_RESULTS}"/apks/*.apk; do
  test -f "${apk}"
  printf '\nAPK: %s\n' "${apk##*/}"
  "${AOSPMAN_REVIEW_BUILD_TOOLS}/aapt" dump badging "${apk}" \
    | rg '^package:|^sdkVersion:|^targetSdkVersion:|^uses-permission:|^native-code:'
  "${AOSPMAN_REVIEW_BUILD_TOOLS}/apksigner" verify --print-certs "${apk}" \
    | rg 'certificate SHA-256 digest:'
done
