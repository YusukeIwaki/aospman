#!/usr/bin/env bash
set -euo pipefail

# Run after avd.py start, before stopping this disposable remote emulator.
readonly AOSPMAN_REVIEW_API="${1:?Expected API 34 or 33}"
readonly AOSPMAN_REVIEW_SERIAL="${2:?Expected the newly started emulator serial}"
readonly AOSPMAN_REVIEW_ADB=/work/src/third_party/android_sdk/public/platform-tools/adb
case "${AOSPMAN_REVIEW_API}" in 34|33) ;; *) exit 1 ;; esac
[[ "${AOSPMAN_REVIEW_SERIAL}" =~ ^emulator-[0-9]+$ ]]
test "$("${AOSPMAN_REVIEW_ADB}" -s "${AOSPMAN_REVIEW_SERIAL}" shell getprop ro.build.version.sdk | tr -d '\r')" = "${AOSPMAN_REVIEW_API}"

exec > >(tee "/work/review-results/api${AOSPMAN_REVIEW_API}-environment.txt") 2>&1
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'serial=%s\n' "${AOSPMAN_REVIEW_SERIAL}"
for property in ro.build.version.sdk ro.build.version.release ro.build.fingerprint ro.product.cpu.abi; do
  printf '%s=' "${property}"
  "${AOSPMAN_REVIEW_ADB}" -s "${AOSPMAN_REVIEW_SERIAL}" shell getprop "${property}"
done
printf 'Google Play Services package version:\n'
"${AOSPMAN_REVIEW_ADB}" -s "${AOSPMAN_REVIEW_SERIAL}" shell dumpsys package com.google.android.gms \
  | rg 'versionCode=|versionName='
printf 'System WebView provider (not the embedded WebViewInstrumentation code):\n'
"${AOSPMAN_REVIEW_ADB}" -s "${AOSPMAN_REVIEW_SERIAL}" shell dumpsys webviewupdate
