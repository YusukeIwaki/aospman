# aospman working agreement

## Project goal

- Investigate whether a custom Android browser can use passkeys after small, reviewable changes to AOSP, Android WebView, or Chromium.
- Treat `.agents/skills/investigate-android-passkeys/references/architecture-baseline.md` as the starting architecture hypothesis, not as timeless truth. Re-check relevant upstream source and official documentation at a pinned revision before drawing conclusions.
- Keep these cases separate: ordinary WebAuthn create/get, Credential Manager privileged-browser/provider approval, conditional mediation, and Chrome Password Manager/Autofill UI integration.

## Start every task

1. Inspect the current repository state and read every applicable `AGENTS.md` before proposing or changing code.
2. For AOSP, Chromium, WebView, WebAuthn, Credential Manager, passkey, Autofill, or browser experiments, use `$investigate-android-passkeys` from `.agents/skills/investigate-android-passkeys`.
3. For any remote checkout, compile, test build, or GCP resource operation, use `$manage-aosp-spot-build` from `.agents/skills/manage-aosp-spot-build`.
4. Prefer the smallest experiment that can falsify the current hypothesis. Do not start a full AOSP or Chromium build when an app-only, source-reading, or targeted component test can answer the question.

## GCP cost and cleanup policy

- Operate only in Google Cloud project `aospman`. Pass `--project=aospman` explicitly even when the active gcloud configuration is correct.
- Run `.agents/skills/manage-aosp-spot-build/scripts/spot-vm.sh audit` before creating resources and again after cleanup.
- Use Spot provisioning for build VMs. Set `--instance-termination-action=DELETE`, a maximum run duration, automatic boot-disk deletion, and the repository's management labels.
- Default maximum lifetime is 8 hours. Never exceed 12 hours without explicit user approval.
- Never create a standard/on-demand build VM, reserved VM, static external IP, retained boot disk, snapshot, custom image, Cloud NAT, bucket, or persistent build cache unless the user explicitly approves the cost and cleanup plan.
- Do not attach a service account or OAuth scopes unless the workload demonstrably needs Google Cloud API access. Grant only the minimum required access when it does.
- Preserve patches, source revisions, build logs, APKs/images needed for the experiment, and checksums before deleting a VM. Do not preserve replaceable source checkouts or build intermediates by default.
- Delete managed build VMs and their disks as soon as the requested artifact or evidence is safely copied out. A stopped VM with an attached disk is not cleaned up.
- On failure, interruption, or preemption, audit for orphaned disks, addresses, snapshots, and images. Report anything that could not be removed.
- Never delete an unlabeled or unrelated resource merely because it appears unused. Inspect ownership and ask before crossing the `managed-by=aospman` boundary.

## Machine selection

- Prefer `c3d-highcpu-90` when the selected zone offers it and both regional C3-family and total CPU quotas have at least 90 vCPUs available.
- As of 2026-08-18, `c3d-highcpu-90` is not offered in `asia-northeast1`; the nearest configured candidate is `asia-east1-a`, and project C3 quota is only 24 vCPUs. Re-run preflight because availability and quota can change.
- Until C3 quota is raised, use `n2-highcpu-96` in `asia-northeast1-b` as the automatic fallback when its live quota and Spot capacity are sufficient. Do not silently request a quota increase.
- Use a 600 GB auto-deleting `pd-balanced` boot disk by default. AOSP alone needs at least 400 GB free; increase disk size only for a documented need such as simultaneous AOSP and Chromium trees.
- Use Ubuntu 22.04 LTS by default: it satisfies current AOSP requirements and matches Chromium's documented Linux build environment. Pin another image when a branch requires it.

## Investigation discipline

- Record upstream repository URL, exact commit/tag, file path, symbol, Android version, WebView/Chrome version, app package/signing identity, credential provider, and relying-party origin for every result.
- Compare at least a control and a treatment. A source change without a baseline on the same device/image is not sufficient evidence.
- Do not claim that replacing only `libwebviewchromium.so` is sufficient without testing provider APK/DEX/resources/signature compatibility.
- Do not attempt to bypass Google Password Manager browser approval, provider trust checks, origin validation, device security, or signature checks. Treat them as external constraints and test with authorized providers/configurations.
- Prefer targeted Chromium/WebView targets before full platform images. Use an AOSP `userdebug` build only when provider selection, framework integration, privileged permissions, or system-image behavior is part of the hypothesis.
- When a device or emulator is available, capture reproducible adb steps, relevant logcat output, screenshots when UI behavior matters, and the exact installed APK/provider versions.

## Completion criteria

- A task is complete only when the result is reproducible, evidence and artifacts are copied to a durable location, temporary cloud resources are deleted or have a verified imminent auto-delete deadline, and the final GCP audit is clean.
- In the handoff, state the tested hypothesis, revisions/configuration, result, remaining uncertainty, artifact locations, and GCP resources created and removed.
