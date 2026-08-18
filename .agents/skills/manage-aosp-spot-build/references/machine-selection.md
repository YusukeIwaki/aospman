# Build VM selection and sizing

## Current baseline

Revalidate every item with `scripts/spot-vm.sh preflight auto`; quotas, zones, images, and Spot capacity change.

| Profile | Machine | Zone | vCPU | RAM | Current project constraint |
| --- | --- | --- | ---: | ---: | --- |
| preferred | `c3d-highcpu-90` | `asia-east1-a` | 90 | 177 GB | `C3_CPUS` quota was 24 vCPUs on 2026-08-18, so this profile needs a quota increase |
| fallback | `n2-highcpu-96` | `asia-northeast1-b` | 96 | 96 GB | `N2_CPUS` was 200 and total `CPUS` was 100 on 2026-08-18 |

`c3d-highcpu-90` was not listed in any `asia-northeast1` zone on 2026-08-18. It was listed in all three `asia-east1` zones. Prefer the nearest viable zone, but let live availability and quota checks decide.

The C3D high-CPU 90 type has 90 vCPUs and 177 GB memory and supports Spot VMs. C3D supports `pd-balanced`, which is the common disk choice used here. Source: <https://docs.cloud.google.com/compute/docs/general-purpose-machines>

## Build sizing

- AOSP documents at least 400 GB free disk and at least 64 GB RAM; Google describes a 72-core/64-GB full build at roughly 40 minutes. Source: <https://source.android.com/docs/setup/start/requirements>
- Chromium's Linux build instructions document at least 100 GB free disk, more than 16 GB RAM recommended, and Ubuntu 22.04 as its current build-infrastructure environment. Source: <https://chromium.googlesource.com/chromium/src/+/main/docs/linux/build_instructions.md>
- Default to a 600 GB auto-deleting `pd-balanced` boot disk. Increase it for side-by-side source trees or unusually large output, not speculatively.
- Default to Ubuntu 22.04 LTS. Pin an older/newer image only when the selected AOSP/Chromium branch documents that requirement.

## Lifetime and interruption

Spot VMs can be preempted at any time. `--instance-termination-action=DELETE` deletes the VM on preemption, and `--max-run-duration` supplies an independent deadline. Source: <https://docs.cloud.google.com/compute/docs/instances/create-use-spot> and <https://docs.cloud.google.com/sdk/gcloud/reference/compute/instances/set-scheduling>

Use 8 hours by default. Raise to no more than 12 hours without explicit approval. Copy durable artifacts off the VM throughout the experiment rather than waiting for shutdown notification.

## Quota interpretation

Check both total regional `CPUS` and the machine-family metric. For the profiles above, use `C3_CPUS` and `N2_CPUS`. A zero `PREEMPTIBLE_CPUS` quota does not by itself prove Spot creation is blocked in this project; a prior E2 Spot validation succeeded against standard family quota. The actual create request remains the capacity test.
