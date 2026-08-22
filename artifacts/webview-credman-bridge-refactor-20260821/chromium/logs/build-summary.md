# Chromium build and test summary

- Revision: `98596990901c11e89a24f6217f1b66513b065026`
- Output: `out/webview-x64`
- GN args: `target_os="android" target_cpu="x64" is_debug=false is_component_build=false symbol_level=0 blink_symbol_level=0 v8_symbol_level=0 use_remoteexec=false treat_warnings_as_errors=false`
- Control `system_webview_64_apk`: passed; SHA-256 `915038de8dbeba31cd6dee5b609a00118d387059df782f155c626a2353a42f9c`.
- Treatment `system_webview_64_apk`: passed; SHA-256 `a10edece2e3fb11493001cb22f7e68dda9d78c20ed913936d7fad0a98661102a`.
- Treatment `chrome_public_apk`: passed, 10,071 steps in 22m57s; SHA-256 `e9528da0c2753821bb6b0e92b7e4e06227990d79f3a71e3fd9b338559e9d5414`. The APK itself was not copied before the maximum-lifetime VM auto-deleted.
- Aggregate `components_junit_tests`: dependency build passed, 6,323 steps in 15m16s.
- Targeted WebAuthn Robolectric run: 178/178 passed across API 29 and API 36.
- `components/webauthn/android:unit_tests`: source-set build passed, 1,854 steps in 5m17s; existing and new factory/delegate unit-test objects compiled. Native gtests were not executed.
- `git cl format --upstream=HEAD` and `git diff --check`: passed on the build checkout.

The raw build/test logs were still on the Spot VM when its maximum lifetime triggered deletion during final transfer. APKs and device evidence central to the experiment had already been copied locally. This summary is derived from the completed command outputs retained in the task transcript; it does not represent a rerun.
