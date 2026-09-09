#!/usr/bin/env bash
# Resume only the pristine control build after a deliberate, clean interruption.
set -euo pipefail
input_dir="$(cd "${1:?Usage: resume-webview-control.sh INPUT_DIRECTORY}" && pwd)"
readonly output_dir=/work/export/webview
export PATH="$HOME/.local/bin:$HOME/depot_tools:$PATH"
cd /work/android16-webview/src
[[ "$(git rev-parse HEAD)" == 98596990901c11e89a24f6217f1b66513b065026 ]]
git diff --exit-code
[[ ! -f "$output_dir/control-SystemWebView64.apk" ]]
printf '%s  %s\n' d6c264ac07a3d80d2d2dba065ba36cc06bad64cb4c1d3eda714aeb9cad815907 "$input_dir/chromium-webview-browser-conditional.patch" | sha256sum -c -
exec > >(tee -a "$output_dir/build.log") 2>&1
trap 'result=$?; printf "%s\n" "$result" > "$output_dir/exit-code.txt"' EXIT
rm -f "$output_dir/exit-code.txt"
cp "$0" "$output_dir/resume-webview-control.sh"
date -u
printf 'Resuming unchanged control build with 24 local jobs.\n'
printf 'control-build\n' > "$output_dir/stage.txt"
autoninja -j24 -C out/webview-arm64 system_webview_64_apk
cp out/webview-arm64/apks/SystemWebView64.apk "$output_dir/control-SystemWebView64.apk"
(cd "$output_dir" && sha256sum control-SystemWebView64.apk > control.sha256)
echo 'CONTROL_READY: copy and verify the control APK on the Mac now.'
git apply --check "$input_dir/chromium-webview-browser-conditional.patch"
git apply "$input_dir/chromium-webview-browser-conditional.patch"
git diff --check
cp "$input_dir/chromium-webview-browser-conditional.patch" "$output_dir/"
printf 'treatment-build\n' > "$output_dir/stage.txt"
autoninja -j24 -C out/webview-arm64 system_webview_64_apk
cp out/webview-arm64/apks/SystemWebView64.apk "$output_dir/treatment-SystemWebView64.apk"
(cd "$output_dir" && sha256sum ./*.apk ./*.patch > SHA256SUMS)
date -u
printf 'ready\n' > "$output_dir/stage.txt"
echo 'WEBVIEW_READY: copy /work/export/webview to the Mac before deleting the VM.'
