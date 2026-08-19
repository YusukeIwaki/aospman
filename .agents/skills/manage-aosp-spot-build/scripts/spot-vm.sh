#!/usr/bin/env bash
set -euo pipefail

readonly AOSPMAN_PROJECT="${AOSPMAN_GCP_PROJECT:-aospman}"
readonly AOSPMAN_DEFAULT_DISK_GB="${AOSPMAN_DISK_GB:-600}"
readonly AOSPMAN_DEFAULT_TTL_HOURS="${AOSPMAN_TTL_HOURS:-8}"
readonly AOSPMAN_ENABLE_NESTED_VIRT="${AOSPMAN_ENABLE_NESTED_VIRT:-0}"
readonly AOSPMAN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  spot-vm.sh audit
  spot-vm.sh list
  spot-vm.sh preflight [auto|preferred|fallback|constrained]
  spot-vm.sh create [auto|preferred|fallback|constrained] [VM_NAME] [TTL_HOURS] [DISK_GB]
  spot-vm.sh bootstrap VM_NAME
  spot-vm.sh ssh VM_NAME
  spot-vm.sh delete VM_NAME
  spot-vm.sh cleanup-managed --confirm

Defaults: auto profile, generated name, 8-hour maximum run duration, 600 GB disk.
Set AOSPMAN_ENABLE_NESTED_VIRT=1 when the build VM must host Cuttlefish.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_tools() {
  command -v gcloud >/dev/null 2>&1 || die 'gcloud is required.'
  command -v jq >/dev/null 2>&1 || die 'jq is required.'
}

profile_values() {
  case "$1" in
    preferred)
      printf '%s\t%s\t%s\t%s\n' 'c3d-highcpu-90' 'asia-east1-a' 'asia-east1' 'C3_CPUS'
      ;;
    fallback)
      printf '%s\t%s\t%s\t%s\n' 'n2-highcpu-96' 'asia-northeast1-b' 'asia-northeast1' 'N2_CPUS'
      ;;
    constrained)
      printf '%s\t%s\t%s\t%s\n' 'n2-highcpu-32' 'asia-northeast1-b' 'asia-northeast1' 'N2_CPUS'
      ;;
    *)
      die "Unknown profile: $1"
      ;;
  esac
}

validate_context() {
  local account
  account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n 1)"
  [[ -n "${account}" ]] || die 'No active gcloud account. Run gcloud auth login.'
  gcloud projects describe "${AOSPMAN_PROJECT}" --format='value(projectId)' >/dev/null
  if [[ "$(gcloud services list --enabled --project="${AOSPMAN_PROJECT}" --filter='config.name=compute.googleapis.com' --format='value(config.name)')" != 'compute.googleapis.com' ]]; then
    die 'Compute Engine API is not enabled for project aospman.'
  fi
}

quota_json() {
  gcloud compute regions describe "$1" --project="${AOSPMAN_PROJECT}" --format=json
}

project_quota_json() {
  gcloud compute project-info describe --project="${AOSPMAN_PROJECT}" --format=json
}

quota_field() {
  local json="$1"
  local metric="$2"
  local field="$3"
  jq -r --arg metric "${metric}" --arg field "${field}" \
    '.quotas[] | select(.metric == $metric) | .[$field]' <<<"${json}"
}

enough_quota() {
  awk -v limit="$1" -v usage="$2" -v need="$3" 'BEGIN { exit !((limit - usage) >= need) }'
}

preflight_profile() {
  local profile="$1"
  local machine zone region family_metric
  IFS=$'\t' read -r machine zone region family_metric <<<"$(profile_values "${profile}")"

  local machine_data
  if ! machine_data="$(gcloud compute machine-types describe "${machine}" \
      --project="${AOSPMAN_PROJECT}" --zone="${zone}" \
      --format='value(guestCpus,memoryMb)' 2>/dev/null)"; then
    printf '%s: unavailable machine %s in %s\n' "${profile}" "${machine}" "${zone}" >&2
    return 1
  fi

  local cpus memory_mb quotas project_quotas total_limit total_usage family_limit family_usage spot_limit spot_usage global_limit global_usage
  read -r cpus memory_mb <<<"${machine_data}"
  quotas="$(quota_json "${region}")"
  project_quotas="$(project_quota_json)"
  total_limit="$(quota_field "${quotas}" 'CPUS' 'limit')"
  total_usage="$(quota_field "${quotas}" 'CPUS' 'usage')"
  family_limit="$(quota_field "${quotas}" "${family_metric}" 'limit')"
  family_usage="$(quota_field "${quotas}" "${family_metric}" 'usage')"
  spot_limit="$(quota_field "${quotas}" 'PREEMPTIBLE_CPUS' 'limit')"
  spot_usage="$(quota_field "${quotas}" 'PREEMPTIBLE_CPUS' 'usage')"
  global_limit="$(quota_field "${project_quotas}" 'CPUS_ALL_REGIONS' 'limit')"
  global_usage="$(quota_field "${project_quotas}" 'CPUS_ALL_REGIONS' 'usage')"

  printf '%s profile\n' "${profile}"
  printf '  machine: %s (%s vCPU, %s MiB RAM)\n' "${machine}" "${cpus}" "${memory_mb}"
  printf '  zone: %s\n' "${zone}"
  printf '  CPUS quota: %s limit, %s used\n' "${total_limit}" "${total_usage}"
  printf '  %s quota: %s limit, %s used\n' "${family_metric}" "${family_limit}" "${family_usage}"
  printf '  CPUS_ALL_REGIONS quota: %s limit, %s used\n' "${global_limit}" "${global_usage}"
  printf '  PREEMPTIBLE_CPUS quota: %s limit, %s used (informational)\n' "${spot_limit}" "${spot_usage}"

  if ! enough_quota "${total_limit}" "${total_usage}" "${cpus}"; then
    printf '  result: insufficient CPUS quota for %s vCPUs\n' "${cpus}" >&2
    return 1
  fi
  if ! enough_quota "${family_limit}" "${family_usage}" "${cpus}"; then
    printf '  result: insufficient %s quota for %s vCPUs\n' "${family_metric}" "${cpus}" >&2
    return 1
  fi
  if ! enough_quota "${global_limit}" "${global_usage}" "${cpus}"; then
    printf '  result: insufficient CPUS_ALL_REGIONS quota for %s vCPUs\n' "${cpus}" >&2
    return 1
  fi
  printf '  result: quota and machine checks passed; Spot capacity is checked at creation time\n'
}

select_profile() {
  local requested="$1"
  if [[ "${requested}" != 'auto' ]]; then
    preflight_profile "${requested}" >&2 || return 1
    printf '%s\n' "${requested}"
    return 0
  fi
  if preflight_profile preferred >&2; then
    printf '%s\n' 'preferred'
    return 0
  fi
  printf 'Preferred profile is not currently viable; checking fallback.\n' >&2
  if preflight_profile fallback >&2; then
    printf '%s\n' 'fallback'
    return 0
  fi
  printf 'Fallback profile is not currently viable; checking constrained profile.\n' >&2
  if preflight_profile constrained >&2; then
    printf '%s\n' 'constrained'
    return 0
  fi
  return 1
}

managed_instances() {
  gcloud compute instances list --project="${AOSPMAN_PROJECT}" \
    --filter='labels.managed-by=aospman AND labels.lifecycle=ephemeral' \
    --format='table(name,zone.basename(),status,machineType.basename(),scheduling.provisioningModel,scheduling.terminationTimestamp,labels.list())'
}

find_zone() {
  local name="$1"
  local zones zone_count
  zones="$(gcloud compute instances list --project="${AOSPMAN_PROJECT}" \
    --filter="name=${name}" --format='value(zone.basename())')"
  zone_count="$(awk 'NF {count++} END {print count + 0}' <<<"${zones}")"
  [[ "${zone_count}" -eq 1 ]] || die "Expected exactly one VM named ${name}; found ${zone_count}."
  printf '%s\n' "${zones}"
}

require_managed_vm() {
  local name="$1"
  local zone="$2"
  local label
  label="$(gcloud compute instances describe "${name}" --project="${AOSPMAN_PROJECT}" --zone="${zone}" --format='value(labels.managed-by)')"
  [[ "${label}" == 'aospman' ]] || die "Refusing to operate on unmanaged VM ${name}."
}

audit() {
  printf 'Project: %s\n' "${AOSPMAN_PROJECT}"
  printf '\nInstances\n'
  gcloud compute instances list --project="${AOSPMAN_PROJECT}" \
    --format='table(name,zone.basename(),status,machineType.basename(),scheduling.provisioningModel,scheduling.terminationTimestamp,labels.list())'
  printf '\nDisks\n'
  gcloud compute disks list --project="${AOSPMAN_PROJECT}" \
    --format='table(name,zone.basename(),sizeGb,type.basename(),status,users.len(),labels.list())'
  printf '\nReserved addresses\n'
  gcloud compute addresses list --project="${AOSPMAN_PROJECT}" \
    --format='table(name,region.basename(),addressType,status,address,users.len())'
  printf '\nSnapshots\n'
  gcloud compute snapshots list --project="${AOSPMAN_PROJECT}" \
    --format='table(name,status,diskSizeGb,storageBytes,creationTimestamp,labels.list())'
  printf '\nCustom images\n'
  gcloud compute images list --project="${AOSPMAN_PROJECT}" --no-standard-images \
    --format='table(name,status,diskSizeGb,creationTimestamp,labels.list())'
}

create_vm() {
  local requested_profile="${1:-auto}"
  local profile
  profile="$(select_profile "${requested_profile}")" || die 'No configured build profile passed preflight.'

  local generated_name="aosp-build-$(date -u +%Y%m%d-%H%M%S)"
  local name="${2:-${generated_name}}"
  local ttl_hours="${3:-${AOSPMAN_DEFAULT_TTL_HOURS}}"
  local disk_gb="${4:-${AOSPMAN_DEFAULT_DISK_GB}}"

  [[ "${name}" =~ ^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$ ]] || die 'VM name is not a valid Compute Engine resource name.'
  [[ "${ttl_hours}" =~ ^[0-9]+$ ]] || die 'TTL_HOURS must be an integer.'
  (( ttl_hours >= 1 && ttl_hours <= 12 )) || die 'TTL_HOURS must be between 1 and 12.'
  [[ "${disk_gb}" =~ ^[0-9]+$ ]] || die 'DISK_GB must be an integer.'
  (( disk_gb >= 400 && disk_gb <= 4096 )) || die 'DISK_GB must be between 400 and 4096.'
  [[ "${AOSPMAN_ENABLE_NESTED_VIRT}" == '0' || "${AOSPMAN_ENABLE_NESTED_VIRT}" == '1' ]] || \
    die 'AOSPMAN_ENABLE_NESTED_VIRT must be 0 or 1.'

  local machine zone region family_metric
  IFS=$'\t' read -r machine zone region family_metric <<<"$(profile_values "${profile}")"

  local storage_quotas ssd_limit ssd_usage
  storage_quotas="$(quota_json "${region}")"
  ssd_limit="$(quota_field "${storage_quotas}" 'SSD_TOTAL_GB' 'limit')"
  ssd_usage="$(quota_field "${storage_quotas}" 'SSD_TOTAL_GB' 'usage')"
  enough_quota "${ssd_limit}" "${ssd_usage}" "${disk_gb}" || \
    die "Insufficient SSD_TOTAL_GB quota for a ${disk_gb} GB pd-balanced disk in ${region} (${ssd_limit} limit, ${ssd_usage} used)."

  local -a nested_virtualization_args=(--no-enable-nested-virtualization)
  if [[ "${AOSPMAN_ENABLE_NESTED_VIRT}" == '1' ]]; then
    [[ "${profile}" == 'fallback' || "${profile}" == 'constrained' ]] || \
      die 'Nested virtualization is configured only for Intel N2 profiles.'
    nested_virtualization_args=(--enable-nested-virtualization)
  fi

  printf 'Creating %s as %s profile in %s.\n' "${name}" "${profile}" "${zone}"
  gcloud compute instances create "${name}" \
    --project="${AOSPMAN_PROJECT}" \
    --zone="${zone}" \
    --machine-type="${machine}" \
    --provisioning-model=SPOT \
    --instance-termination-action=DELETE \
    --max-run-duration="${ttl_hours}h" \
    --maintenance-policy=TERMINATE \
    --no-restart-on-failure \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-type=pd-balanced \
    --boot-disk-size="${disk_gb}GB" \
    --boot-disk-auto-delete \
    --no-service-account \
    --no-scopes \
    "${nested_virtualization_args[@]}" \
    --labels=managed-by=aospman,workload=android-build,lifecycle=ephemeral \
    --quiet

  gcloud compute instances describe "${name}" --project="${AOSPMAN_PROJECT}" --zone="${zone}" \
    --format='yaml(name,status,machineType.basename(),zone.basename(),advancedMachineFeatures.enableNestedVirtualization,scheduling.provisioningModel,scheduling.instanceTerminationAction,scheduling.terminationTimestamp,disks[].autoDelete,labels)'
  printf 'Bootstrap: %s bootstrap %s\n' "$0" "${name}"
  printf 'Cleanup:   %s delete %s\n' "$0" "${name}"
}

delete_vm() {
  local name="$1"
  local zone
  zone="$(find_zone "${name}")"
  require_managed_vm "${name}" "${zone}"
  gcloud compute instances delete "${name}" --project="${AOSPMAN_PROJECT}" --zone="${zone}" --delete-disks=all --quiet
}

cleanup_managed() {
  [[ "${1:-}" == '--confirm' ]] || die 'Run list first, then pass --confirm to delete all managed ephemeral VMs.'
  local rows
  rows="$(gcloud compute instances list --project="${AOSPMAN_PROJECT}" \
    --filter='labels.managed-by=aospman AND labels.lifecycle=ephemeral' \
    --format='value(name,zone.basename())')"
  if [[ -z "${rows}" ]]; then
    printf 'No managed ephemeral VMs found.\n'
    return 0
  fi
  while read -r name zone; do
    [[ -n "${name}" && -n "${zone}" ]] || continue
    printf 'Deleting managed VM %s in %s and all attached disks.\n' "${name}" "${zone}"
    gcloud compute instances delete "${name}" --project="${AOSPMAN_PROJECT}" --zone="${zone}" --delete-disks=all --quiet
  done <<<"${rows}"
}

main() {
  require_tools
  validate_context
  local command="${1:-}"
  case "${command}" in
    audit)
      audit
      ;;
    list)
      managed_instances
      ;;
    preflight)
      select_profile "${2:-auto}" >/dev/null
      ;;
    create)
      create_vm "${2:-auto}" "${3:-}" "${4:-}" "${5:-}"
      ;;
    bootstrap)
      [[ -n "${2:-}" ]] || die 'bootstrap requires VM_NAME.'
      local bootstrap_zone
      bootstrap_zone="$(find_zone "$2")"
      require_managed_vm "$2" "${bootstrap_zone}"
      gcloud compute ssh "$2" --project="${AOSPMAN_PROJECT}" --zone="${bootstrap_zone}" \
        --command='bash -s' < "${AOSPMAN_SCRIPT_DIR}/bootstrap-build-vm.sh"
      ;;
    ssh)
      [[ -n "${2:-}" ]] || die 'ssh requires VM_NAME.'
      local ssh_zone
      ssh_zone="$(find_zone "$2")"
      require_managed_vm "$2" "${ssh_zone}"
      gcloud compute ssh "$2" --project="${AOSPMAN_PROJECT}" --zone="${ssh_zone}"
      ;;
    delete)
      [[ -n "${2:-}" ]] || die 'delete requires VM_NAME.'
      delete_vm "$2"
      ;;
    cleanup-managed)
      cleanup_managed "${2:-}"
      ;;
    *)
      usage
      [[ -n "${command}" ]] && exit 1
      ;;
  esac
}

main "$@"
