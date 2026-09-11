#!/usr/bin/env bash
set -euo pipefail

# Launch detached, after fixing a treatment-only failure and preserving its log:
# nohup bash /work/resume-treatment.sh > /work/review-results/resume-console.log 2>&1 < /dev/null &
exec 9>/work/credman-review-pipeline.lock
flock -n 9
trap 'result=$?; printf "%s\n" "${result}" > /work/review-results/pipeline-exit-code.txt; exit "${result}"' EXIT
date -u '+%Y-%m-%dT%H:%M:%SZ' > /work/review-results/resume-started-at.txt
sha256sum /work/chromium-webauthn-credman-bridge.patch \
  > /work/review-results/treatment/patch-sha256.txt
bash /work/build-and-test.sh treatment --resume \
  > /work/review-results/treatment/console-resume.log 2>&1
bash /work/build-and-test-chrome.sh treatment \
  > /work/review-results/treatment/chrome-console.log 2>&1
bash /work/verify-chrome-cleanup.sh
bash /work/record-apks.sh treatment
date -u '+%Y-%m-%dT%H:%M:%SZ' > /work/review-results/pipeline-finished-at.txt
