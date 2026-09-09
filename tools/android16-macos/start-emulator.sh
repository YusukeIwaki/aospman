#!/usr/bin/env bash
set -euo pipefail
image_dir="$(cd "${1:?Usage: start-emulator.sh EXTRACTED_IMAGE_DIRECTORY [emulator options]}" && pwd)"
shift
sdk_dir="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
avd_root="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
readonly avd_name=aospman_android16
avd_dir="$avd_root/$avd_name.avd"
[[ "$(uname -sm)" == 'Darwin arm64' ]] || { echo 'This launcher targets Apple Silicon macOS.' >&2; exit 1; }
[[ -x "$sdk_dir/emulator/emulator" ]]
for filename in system.img vendor.img ramdisk.img kernel-ranchu userdata.img build.prop VerifiedBootParams.textproto source.properties; do
  [[ -s "$image_dir/$filename" ]] || { echo "Missing image artifact: $filename" >&2; exit 1; }
done
[[ -s "$image_dir/../image-SHA256SUMS" ]] || { echo 'Missing image-SHA256SUMS.' >&2; exit 1; }
(cd "$image_dir" && shasum -a 256 -c ../image-SHA256SUMS)
if [[ -e "$avd_dir" || -e "$avd_root/$avd_name.ini" ]]; then
  [[ -f "$avd_dir/aospman-image-path" ]] && [[ "$(cat "$avd_dir/aospman-image-path")" == "$image_dir" ]] || {
    echo 'An AVD with this name already exists and is not registered to this image. Inspect it first.' >&2
    exit 1
  }
else
  mkdir -p "$avd_dir"
  printf '%s\n' "$image_dir" > "$avd_dir/aospman-image-path"
  cat > "$avd_root/$avd_name.ini" <<EOF
avd.ini.encoding=UTF-8
path=$avd_dir
target=android-36
EOF
  cat > "$avd_dir/config.ini" <<EOF
AvdId=$avd_name
avd.ini.displayname=Aospman Android 16 patched WebView
avd.ini.encoding=UTF-8
abi.type=arm64-v8a
hw.cpu.arch=arm64
hw.cpu.ncore=4
hw.ramSize=4096
hw.gpu.enabled=yes
hw.gpu.mode=auto
hw.keyboard=yes
hw.lcd.width=720
hw.lcd.height=1280
hw.lcd.density=320
hw.mainKeys=no
hw.battery=yes
hw.audioInput=no
hw.camera.back=none
hw.camera.front=none
disk.dataPartition.size=8G
image.sysdir.1=$image_dir/
tag.id=aospman
tag.display=Aospman AOSP
target=android-36
PlayStore.enabled=false
fastboot.forceColdBoot=yes
showDeviceFrame=no
EOF
fi
export ANDROID_AVD_HOME="$avd_root"
exec "$sdk_dir/emulator/emulator" -avd "$avd_name" -port 5560 -no-snapshot -no-boot-anim "$@"
