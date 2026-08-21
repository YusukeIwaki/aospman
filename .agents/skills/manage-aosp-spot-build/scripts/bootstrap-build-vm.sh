#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -o Acquire::http::No-Cache=true
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  bison \
  build-essential \
  ca-certificates \
  curl \
  file \
  flex \
  fontconfig \
  git-core \
  gnupg \
  lib32z1-dev \
  libc6-dev-i386 \
  libgl1-mesa-dev \
  libxml2-utils \
  libx11-dev \
  lsb-release \
  ninja-build \
  openjdk-17-jdk \
  python3 \
  python3-pip \
  rsync \
  unzip \
  x11proto-core-dev \
  xsltproc \
  zip \
  zlib1g-dev

sudo install -d -o "$(id -u)" -g "$(id -g)" /work
install -d "${HOME}/.local/bin"
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "${HOME}/.local/bin/repo"
chmod 0755 "${HOME}/.local/bin/repo"

if [[ ! -d "${HOME}/depot_tools/.git" ]]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "${HOME}/depot_tools"
fi

if ! grep -Fq '# aospman build tools' "${HOME}/.profile" 2>/dev/null; then
  {
    printf '\n# aospman build tools\n'
    printf 'export PATH="$HOME/.local/bin:$HOME/depot_tools:$PATH"\n'
  } >> "${HOME}/.profile"
fi

export PATH="${HOME}/.local/bin:${HOME}/depot_tools:${PATH}"
git config --global color.ui auto

printf 'Build VM bootstrap complete.\n'
printf 'Work directory: /work\n'
printf 'Logical CPUs: %s\n' "$(nproc)"
printf 'Memory: %s\n' "$(free -h | awk '/^Mem:/ {print $2}')"
printf 'Disk: %s\n' "$(df -h /work | awk 'NR == 2 {print $2 " total, " $4 " free"}')"
printf 'Start a new shell or run: source ~/.profile\n'
