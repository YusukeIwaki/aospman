#!/usr/bin/env bash
set -euo pipefail

# Optional prefetch during compilation; the test runners also install on demand.
export PATH="/work/src/third_party/depot_tools:${HOME}/depot_tools:${PATH}"
export DEPOT_TOOLS_UPDATE=0
mkdir -p /work/review-results
exec > >(tee -a /work/review-results/avd-install.log) 2>&1
trap 'result=$?; printf "%s\n" "${result}" > /work/review-results/avd-install.exit; exit "${result}"' EXIT

cd /work/src
for api_level in 34 33; do
  tools/android/avd/avd.py install \
    --avd-config "tools/android/avd/proto/android_${api_level}_google_apis_x64_local.textpb"
done
