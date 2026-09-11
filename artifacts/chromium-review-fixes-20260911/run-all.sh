#!/usr/bin/env bash
set -euo pipefail

# Launch on the disposable VM, detached from the SSH output connection:
# nohup bash /work/run-all.sh > /work/review-results/pipeline-console.log 2>&1 < /dev/null &
# This also resumes the pristine control after an interrupted incremental build.
# A treatment already applied to the source is intentionally rejected below.
exec 9>/work/credman-review-pipeline.lock
flock -n 9
trap 'result=$?; printf "%s\n" "${result}" > /work/review-results/pipeline-exit-code.txt; exit "${result}"' EXIT

cd /work/src
git diff --exit-code
git diff --cached --exit-code
date -u '+%Y-%m-%dT%H:%M:%SZ' > /work/review-results/pipeline-started-at.txt

bash /work/build-and-test.sh control \
  > /work/review-results/control/console-resume.log 2>&1
bash /work/build-and-test-chrome.sh control \
  > /work/review-results/control/chrome-console.log 2>&1
bash /work/record-apks.sh control

mkdir -p /work/review-results/treatment
sha256sum /work/chromium-webauthn-credman-bridge.patch \
  > /work/review-results/treatment/patch-sha256.txt
bash /work/build-and-test.sh treatment \
  > /work/review-results/treatment/console.log 2>&1
bash /work/build-and-test-chrome.sh treatment \
  > /work/review-results/treatment/chrome-console.log 2>&1
bash /work/record-apks.sh treatment
date -u '+%Y-%m-%dT%H:%M:%SZ' > /work/review-results/pipeline-finished-at.txt
