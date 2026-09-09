#!/usr/bin/env bash
# Run on a fresh managed Linux VM after the WebView APKs have been copied to the Mac.
set -eo pipefail
input_dir="$(cd "${1:?Usage: build-aosp.sh INPUT_DIRECTORY [--resume-sync|--repair-sync|--resume-build]}" && pwd)"
readonly tag=android-16.0.0_r4
readonly manifest_revision=15128c9e27cfa599c48d294babd39286ee8f1426
readonly work_dir=/work/android16-aosp
readonly output_dir=/work/export/aosp
export PATH="$HOME/.local/bin:$HOME/depot_tools:$PATH"
[[ "$(uname -sm)" == 'Linux x86_64' ]] || { echo 'Requires Linux x86_64.' >&2; exit 1; }
resume_sync=false
resume_build=false
if [[ -e "$work_dir" ]]; then
  [[ -s "$output_dir/exit-code.txt" && "$(cat "$output_dir/exit-code.txt")" != 0 ]] || {
    echo 'Work directory exists without a stopped, unsuccessful build. Inspect it first.' >&2; exit 1;
  }
  case "${2:-}:$(cat "$output_dir/stage.txt")" in
    --resume-sync:sync|--repair-sync:sync) resume_sync=true ;;
    --resume-build:build|--resume-build:package) resume_build=true ;;
    *) echo 'Resume option does not match the stopped build stage.' >&2; exit 1 ;;
  esac
fi
build_jobs="${AOSPMAN_BUILD_JOBS:-12}"
[[ "$build_jobs" =~ ^[0-9]+$ ]] && (( build_jobs >= 1 && build_jobs <= 24 )) || {
  echo 'AOSPMAN_BUILD_JOBS must be an integer from 1 to 24.' >&2; exit 1;
}
[[ -s "$input_dir/treatment-SystemWebView64.apk" ]]
[[ -s "$input_dir/aosp-webview-integration.patch" ]]
(cd "$input_dir" && sha256sum -c treatment.sha256)
mkdir -p "$work_dir" "$output_dir"
rm -f "$output_dir/exit-code.txt"
exec > >(tee -a "$output_dir/build.log") 2>&1
trap 'result=$?; printf "%s\n" "$result" > "$output_dir/exit-code.txt"' EXIT
date -u
cp "$0" "$output_dir/build-aosp.sh"
if ! "$resume_build"; then
# A fresh disposable build VM has no developer identity. Avoid repo's first-run prompt.
git config --global user.name 'Aospman Build'
git config --global user.email 'aospman-build@localhost'
# Temporary swap lives only on this VM's auto-deleting boot disk.
if ! "$resume_sync"; then
  printf 'checkout\n' > "$output_dir/stage.txt"
  [[ ! -e /work/aospman-build.swap ]]
  sudo fallocate -l 32G /work/aospman-build.swap
  sudo chmod 600 /work/aospman-build.swap
  sudo mkswap /work/aospman-build.swap
  sudo swapon /work/aospman-build.swap
fi
cd "$work_dir"
if ! "$resume_sync"; then
  repo init -u https://android.googlesource.com/platform/manifest -b "$tag" --depth=1 --no-clone-bundle
fi
[[ "$(git -C .repo/manifests rev-parse HEAD)" == "$manifest_revision" ]]
printf 'sync\n' > "$output_dir/stage.txt"
sync_ok=false
sync_repair_args=()
# Opt in only after verifying this disposable tree contains no local work.
# An interrupted fail-fast sync can leave partial checkouts with an empty index.
if [[ "${2:-}" == --repair-sync ]]; then
  sync_repair_args+=(--force-checkout)
fi
for jobs in 8 4 2; do
  if repo sync -c -j"$jobs" --no-clone-bundle --no-tags "${sync_repair_args[@]}"; then
    sync_ok=true
    break
  fi
  echo "repo sync failed at $jobs jobs; retaining objects and waiting before a lower-concurrency retry."
  sleep 20
done
"$sync_ok"
repo manifest -r -o "$output_dir/aosp-manifest.xml"
fi
cd "$work_dir"
[[ "$(git -C .repo/manifests rev-parse HEAD)" == "$manifest_revision" ]]
printf 'configure\n' > "$output_dir/stage.txt"
source build/envsetup.sh
lunch sdk_phone64_arm64-aosp_current-userdebug
get_build_var TARGET_PRODUCT > "$output_dir/product.txt"
get_build_var PLATFORM_VERSION > "$output_dir/platform-version.txt"
[[ "$(get_build_var PLATFORM_VERSION)" == 16 ]]
webview_version="$(get_build_var RELEASE_PACKAGE_WEBVIEW_VERSION)"
[[ -n "$webview_version" && "$webview_version" != */* ]]
webview_apk="external/chromium-webview/$webview_version/arm64/webview.apk"
[[ -s "$webview_apk" ]]
printf '%s\n' "$webview_version" > "$output_dir/original-webview-version.txt"
if "$resume_build"; then
  git -C external/chromium-webview apply --reverse --check "$input_dir/aosp-webview-integration.patch"
  cmp "$input_dir/treatment-SystemWebView64.apk" "$webview_apk"
else
  git -C external/chromium-webview apply --check "$input_dir/aosp-webview-integration.patch"
  git -C external/chromium-webview apply "$input_dir/aosp-webview-integration.patch"
  cp "$input_dir/treatment-SystemWebView64.apk" "$webview_apk"
fi
cp "$input_dir/aosp-webview-integration.patch" "$output_dir/"
sha256sum "$webview_apk" > "$output_dir/webview-input.sha256"
export BUILD_NUMBER=aospman-android16-arm64
printf 'build\n' > "$output_dir/stage.txt"
export NINJA_HIGHMEM_NUM_JOBS=2
printf 'jobs=%s\nhighmem_jobs=%s\n' "$build_jobs" "$NINJA_HIGHMEM_NUM_JOBS" > "$output_dir/build-parallelism.txt"
m -j"$build_jobs"
printf 'package\n' > "$output_dir/stage.txt"
product_out="$(get_abs_build_var PRODUCT_OUT)"
image_dir="$output_dir/image"
mkdir -p "$image_dir"
# QEMU images contain the partition layout expected by Android Emulator.
# system-qemu.img includes the dynamic partitions, including patched /product.
cp "$product_out/system-qemu.img" "$image_dir/system.img"
cp "$product_out/vendor-qemu.img" "$image_dir/vendor.img"
cp "$product_out/ramdisk-qemu.img" "$image_dir/ramdisk.img"
cp "$product_out/kernel-ranchu" "$image_dir/kernel-ranchu"
cp "$product_out/userdata.img" "$image_dir/userdata.img"
cp "$product_out/system/build.prop" "$image_dir/build.prop"
cp "$product_out/VerifiedBootParams.textproto" "$image_dir/"
for filename in advancedFeatures.ini encryptionkey.img emulator-info.txt; do
  if [[ -f "$product_out/$filename" ]]; then cp "$product_out/$filename" "$image_dir/"; fi
done
cat > "$image_dir/source.properties" <<EOF
Pkg.Desc=Aospman Android 16 arm64 with Chromium WebView conditional passkeys
Pkg.Revision=1
AndroidVersion.ApiLevel=36
SystemImage.Abi=arm64-v8a
SystemImage.TagId=aospman
SystemImage.TagDisplay=Aospman AOSP
SystemImage.GpuSupport=true
EOF
cmp "$webview_apk" "$product_out/product/app/webview/webview.apk"
cp "$product_out/product/app/webview/webview.apk" "$output_dir/integrated-webview.apk"
(cd "$image_dir" && sha256sum ./* > ../image-SHA256SUMS)
tar -C "$output_dir" -czf "$output_dir/android16-arm64-image.tar.gz" image
(cd "$output_dir" && sha256sum android16-arm64-image.tar.gz integrated-webview.apk > SHA256SUMS)
date -u
printf 'ready\n' > "$output_dir/stage.txt"
echo 'AOSP_READY: copy the archive, manifest, patches, hashes and logs to the Mac before deleting the VM.'
