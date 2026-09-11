#!/usr/bin/env bash
set -euo pipefail

# Run only on the approved, ephemeral Linux build VM after spot-vm bootstrap.
readonly AOSPMAN_REVIEW_BASE=e972dac6c18230a8cbae2a744593916a7da1d82c
readonly AOSPMAN_REVIEW_RESULTS=/work/review-results
export PATH="${HOME}/depot_tools:${PATH}"
export DEPOT_TOOLS_UPDATE=0
mkdir -p "${AOSPMAN_REVIEW_RESULTS}"
exec > >(tee -a "${AOSPMAN_REVIEW_RESULTS}/prepare.log") 2>&1
trap 'result=$?; printf "%s\n" "${result}" > /work/review-results/prepare.exit; exit "${result}"' EXIT

cd /work
if [[ -e src || -e .gclient ]]; then
  printf 'Refusing to initialize over an existing Chromium checkout.\n' >&2
  exit 1
fi
gclient config --spec='solutions = [{"name": "src", "url": "https://chromium.googlesource.com/chromium/src.git", "managed": False, "custom_deps": {}, "custom_vars": {}}]; target_os = ["android"];'
gclient sync --nohooks --no-history --revision "src@${AOSPMAN_REVIEW_BASE}" --jobs 16
cd /work/src
test "$(git rev-parse HEAD)" = "${AOSPMAN_REVIEW_BASE}"
git rev-parse HEAD | tee "${AOSPMAN_REVIEW_RESULTS}/chromium-base.txt"
git -C "${HOME}/depot_tools" rev-parse HEAD | tee "${AOSPMAN_REVIEW_RESULTS}/bootstrap-depot-tools.txt"
sudo build/install-build-deps.sh --android --no-prompt
gclient runhooks
# Build with the depot_tools revision pinned by Chromium, not the bootstrap
# clone. Its own Python/CIPD runtime needs initialization as well.
PATH="/work/src/third_party/depot_tools:${PATH}" \
  /work/src/third_party/depot_tools/ensure_bootstrap
test -s third_party/depot_tools/python3_bin_reldir.txt
sudo modprobe kvm_intel
sudo usermod -a -G kvm "$(id -un)"
ls -l /dev/kvm
df -h /work
printf 'Checkout ready. Start the build in a new SSH session to use the kvm group.\n'
