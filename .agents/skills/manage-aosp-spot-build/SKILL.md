---
name: manage-aosp-spot-build
description: Create, bootstrap, use, audit, and remove cost-safe Google Cloud Spot VMs for AOSP, Chromium, Android WebView, or other large Android builds in project aospman. Use whenever work needs a remote high-CPU build machine, gcloud Compute Engine resources, build artifact retrieval, quota/capacity selection, or cleanup of potentially billable build resources. Do not use for local-only source reading or small local builds.
---

# Manage AOSP Spot Builds

Use the bundled lifecycle script instead of composing ad hoc `gcloud compute` commands. It encodes the project boundary, live quota checks, Spot-only scheduling, an auto-delete deadline, labels, and boot-disk cleanup.

## Workflow

1. Read the root `AGENTS.md` cost policy.
2. Run `scripts/spot-vm.sh audit` before changing cloud state.
3. Run `scripts/spot-vm.sh preflight auto`.
4. Reuse an existing managed VM only when it is still needed for the same experiment and has enough remaining lifetime. Otherwise create a new ephemeral VM with `scripts/spot-vm.sh create auto`.
5. Run `scripts/spot-vm.sh bootstrap VM_NAME` once on a new VM.
6. Pin source revisions before modifying code. Store work under `/work`.
7. Copy patches, logs, APKs/system images, revision manifests, and checksums out before teardown.
8. Run `scripts/spot-vm.sh delete VM_NAME`, then `scripts/spot-vm.sh audit`.

If the task or agent stops unexpectedly, the VM must still delete itself at the configured maximum run duration. Do not remove that guardrail.

## Machine decision

- Let `auto` select the profile from live machine availability and quota.
- Prefer `c3d-highcpu-90` in `asia-east1-a` when both `C3_CPUS` and total `CPUS` have 90 vCPUs available.
- Fall back to `n2-highcpu-96` in `asia-northeast1-b` when the preferred profile is unavailable or under quota and the fallback has quota.
- Stop and report the exact quota/capacity problem when neither profile passes. Do not request quota changes or choose a substantially different paid resource without user direction.
- Read `references/machine-selection.md` when changing machine, zone, disk, image, or lifetime defaults.

Spot capacity is not guaranteed even after preflight. If creation returns a capacity error, try another zone in the same profile only after verifying machine availability and quota. Do not fall back to a standard VM.

## Cost and resource invariants

- Keep project fixed to `aospman`; pass it explicitly.
- Use Spot with termination action `DELETE`.
- Keep maximum lifetime at 8 hours by default and at most 12 hours without explicit approval.
- Use an auto-deleting boot disk and ephemeral external IP. Do not retain disks on deletion.
- Apply `managed-by=aospman`, `workload=android-build`, and `lifecycle=ephemeral` labels.
- Attach no service account and no OAuth scopes by default.
- Create no snapshot, image, static address, bucket, reservation, or persistent cache by default.
- Delete only exact resources created by this workflow. `cleanup-managed --confirm` is a last-resort cleanup for labeled ephemeral VMs; inspect its list first.
- Treat stopped instances, unattached disks, snapshots, custom images, and reserved static addresses as potential charges until verified otherwise.

## Build continuity

Assume preemption can happen at any time. Keep source changes as small commits or patch files and copy them out early. Stream or periodically copy long build logs. Upload final artifacts before teardown; never rely on the Spot boot disk as durable storage.

When a task needs a persistent cache, explain its expected savings, hourly/monthly storage cost, retention limit, ownership label, and deletion command, then obtain explicit approval before creating it.

## Commands

Run commands from this skill directory or use absolute paths.

```bash
scripts/spot-vm.sh audit
scripts/spot-vm.sh preflight auto
scripts/spot-vm.sh create auto
scripts/spot-vm.sh bootstrap VM_NAME
scripts/spot-vm.sh ssh VM_NAME
scripts/spot-vm.sh delete VM_NAME
scripts/spot-vm.sh audit
```

Use `scripts/spot-vm.sh list` to inspect only managed build VMs. Use `scripts/spot-vm.sh cleanup-managed --confirm` only after verifying that all listed managed ephemeral VMs are disposable.

## Handoff

Report:

- project, profile, machine type, zone, disk, and maximum lifetime;
- source revisions and build commands;
- retained artifact paths and checksums;
- every resource created and deleted;
- the final audit result and any resource that remains.
