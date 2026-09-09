#!/usr/bin/env bash
# Run on a freshly bootstrapped, managed Linux build VM. No cloud resources are created here.
set -euo pipefail
input_dir="$(cd "${1:?Usage: build-webview.sh INPUT_DIRECTORY}" && pwd)"
readonly revision=98596990901c11e89a24f6217f1b66513b065026
readonly work_dir=/work/android16-webview
readonly output_dir=/work/export/webview
readonly patch_sha=d6c264ac07a3d80d2d2dba065ba36cc06bad64cb4c1d3eda714aeb9cad815907
export PATH="$HOME/.local/bin:$HOME/depot_tools:$PATH"
[[ "$(uname -sm)" == 'Linux x86_64' ]] || { echo 'Requires Linux x86_64.' >&2; exit 1; }
[[ ! -e "$work_dir" ]] || { echo 'Work directory exists; inspect it before resuming manually.' >&2; exit 1; }
printf '%s  %s\n' "$patch_sha" "$input_dir/chromium-webview-browser-conditional.patch" | sha256sum -c -
mkdir -p "$work_dir/src" "$output_dir"
exec > >(tee -a "$output_dir/build.log") 2>&1
trap 'result=$?; printf "%s\n" "$result" > "$output_dir/exit-code.txt"' EXIT
date -u
cp "$0" "$output_dir/build-webview.sh"
printf 'checkout\n' > "$output_dir/stage.txt"
# An 8 GiB spike guard on the same auto-deleting boot disk, not a persistent cache.
[[ ! -e /work/aospman-webview.swap ]]
sudo fallocate -l 8G /work/aospman-webview.swap
sudo chmod 600 /work/aospman-webview.swap
sudo mkswap /work/aospman-webview.swap
sudo swapon /work/aospman-webview.swap
git -C "$HOME/depot_tools" rev-parse HEAD > "$output_dir/depot-tools-revision.txt"
cd "$work_dir"
cat > .gclient <<EOF
solutions = [{"name": "src", "url": "https://chromium.googlesource.com/chromium/src.git", "managed": False, "custom_deps": {}, "custom_vars": {}}]
target_os = ["android"]
EOF
git -C src init
git -C src remote add origin https://chromium.googlesource.com/chromium/src.git
git -C src fetch --depth=1 origin "$revision"
git -C src checkout --detach FETCH_HEAD
printf 'dependencies\n' > "$output_dir/stage.txt"
gclient sync --nohooks --no-history --jobs=16 --revision "src@$revision"
cd src
./build/install-build-deps.sh --no-prompt --no-chromeos-fonts
gclient runhooks --force
git rev-parse HEAD > "$output_dir/chromium-revision.txt"
gclient revinfo > "$output_dir/dependency-revisions.txt"
cp chrome/VERSION "$output_dir/VERSION"
gn gen out/webview-arm64 --args='target_os="android" target_cpu="arm64" is_debug=false is_component_build=false symbol_level=0 blink_symbol_level=0 v8_symbol_level=0 use_remoteexec=false treat_warnings_as_errors=false'
cp out/webview-arm64/args.gn "$output_dir/args.gn"
printf 'control-build\n' > "$output_dir/stage.txt"
autoninja -j16 -C out/webview-arm64 system_webview_64_apk
cp out/webview-arm64/apks/SystemWebView64.apk "$output_dir/control-SystemWebView64.apk"
(cd "$output_dir" && sha256sum control-SystemWebView64.apk > control.sha256)
echo 'CONTROL_READY: copy and verify the control APK on the Mac now.'
git apply --check "$input_dir/chromium-webview-browser-conditional.patch"
git apply "$input_dir/chromium-webview-browser-conditional.patch"
git diff --check
cp "$input_dir/chromium-webview-browser-conditional.patch" "$output_dir/"
printf 'treatment-build\n' > "$output_dir/stage.txt"
autoninja -j16 -C out/webview-arm64 system_webview_64_apk
cp out/webview-arm64/apks/SystemWebView64.apk "$output_dir/treatment-SystemWebView64.apk"
(cd "$output_dir" && sha256sum ./*.apk ./*.patch > SHA256SUMS)
date -u
printf 'ready\n' > "$output_dir/stage.txt"
echo 'WEBVIEW_READY: copy /work/export/webview to the Mac before deleting the VM.'
