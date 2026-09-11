#!/usr/bin/env bash
set -euo pipefail

# Ephemeral swap within the already allocated 500GB boot disk. No extra disk,
# persistent cache, or fstab entry is created; VM deletion removes this file.
readonly AOSPMAN_REVIEW_SWAP=/work/credman-review.swap
test ! -e "${AOSPMAN_REVIEW_SWAP}"
exec > >(tee /work/review-results/swap-setup.log) 2>&1
sudo fallocate -l 16G "${AOSPMAN_REVIEW_SWAP}"
sudo chmod 600 "${AOSPMAN_REVIEW_SWAP}"
sudo mkswap "${AOSPMAN_REVIEW_SWAP}"
sudo swapon "${AOSPMAN_REVIEW_SWAP}"
swapon --show
free -h
