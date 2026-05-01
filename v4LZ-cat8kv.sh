#!/usr/bin/env bash

set -euo pipefail

# ------------------------------------------------------------
# Cisco Catalyst 8000V Local Zone EC2 Instance Type Validator
# Phase 1: Optionally enable all scanned Local Zones
# Phase 2: Check Cisco Catalyst 8000V EC2 instance support
# ------------------------------------------------------------
#
# Check only:
#   ./v4LZ-cat8kv.sh
#
# Enable all scanned Local Zones, then check:
#   ./v4LZ-cat8kv.sh --enable-local-zones
#
# Requirements:
#   - AWS CLI v2
#   - AWS credentials configured
#   - IAM permissions:
#       ec2:DescribeAvailabilityZones
#       ec2:DescribeInstanceTypeOfferings
#       ec2:ModifyAvailabilityZoneGroup
# ------------------------------------------------------------

ENABLE_LOCAL_ZONES=false

if [[ "${1:-}" == "--enable-local-zones" ]]; then
  ENABLE_LOCAL_ZONES=true
fi

OPTION_A_TYPES=(
  "c6in.large"
  "c6in.xlarge"
  "c6in.2xlarge"
  "c6in.8xlarge"
)

OPTION_B_TYPES=(
  "c5.large"
  "c5.xlarge"
  "c5.2xlarge"
  "c5.9xlarge"
  "c5n.4xlarge"
  "c5n.18xlarge"
)

OPTION_C_TYPES=(
  "t3.medium"
)

FAMILIES=(
  "c6in"
  "c5"
  "c5n"
  "t3"
)

LOCAL_ZONES=(
  "Dallas|us-east-1|us-east-1-dfw-2a"
  "Chicago|us-east-1|us-east-1-chi-2a"
  "New York|us-east-1|us-east-1-nyc-2a"
  "Los Angeles|us-west-2|us-west-2-lax-1a"
  "Atlanta|us-east-1|us-east-1-atl-2a"
  "Boston|us-east-1|us-east-1-bos-1a"
  "Houston|us-east-1|us-east-1-iah-2a"
  "Miami|us-east-1|us-east-1-mia-2a"
)

get_zone_status_raw() {
  local region="$1"
  local local_zone="$2"

  aws ec2 describe-availability-zones \
    --region "${region}" \
    --all-availability-zones \
    --filters "Name=zone-name,Values=${local_zone}" \
    --query "AvailabilityZones[0].[ZoneName,ZoneType,GroupName,OptInStatus,State]" \
    --output text 2>/dev/null || true
}

get_zone_opt_in_status() {
  local region="$1"
  local local_zone="$2"

  aws ec2 describe-availability-zones \
    --region "${region}" \
    --all-availability-zones \
    --filters "Name=zone-name,Values=${local_zone}" \
    --query "AvailabilityZones[0].OptInStatus" \
    --output text 2>/dev/null || true
}

get_zone_group_name() {
  local region="$1"
  local local_zone="$2"

  aws ec2 describe-availability-zones \
    --region "${region}" \
    --all-availability-zones \
    --filters "Name=zone-name,Values=${local_zone}" \
    --query "AvailabilityZones[0].GroupName" \
    --output text 2>/dev/null || true
}

enable_local_zone_group() {
  local region="$1"
  local group_name="$2"

  aws ec2 modify-availability-zone-group \
    --region "${region}" \
    --group-name "${group_name}" \
    --opt-in-status opted-in \
    --output text >/dev/null
}

get_all_instance_types_in_zone() {
  local region="$1"
  local local_zone="$2"

  aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters "Name=location,Values=${local_zone}" \
    --region "${region}" \
    --query "InstanceTypeOfferings[].InstanceType" \
    --output text 2>/dev/null | tr '\t' '\n' | sort -V || true
}

check_supported_types() {
  local all_types="$1"
  shift

  local supported_types=("$@")
  local found=()

  for supported in "${supported_types[@]}"; do
    if echo "${all_types}" | grep -qx "${supported}"; then
      found+=("${supported}")
    fi
  done

  printf "%s\n" "${found[@]}"
}

print_supported_result() {
  local option_name="$1"
  local found_types="$2"

  if [[ -n "${found_types}" ]]; then
    echo "  ${option_name}: SUPPORTED"
    echo "${found_types}" | sed 's/^/    - /'
  else
    echo "  ${option_name}: NOT SUPPORTED"
  fi
}

print_family_inventory() {
  local all_types="$1"
  local family="$2"

  local family_types
  family_types=$(echo "${all_types}" | grep -E "^${family}\." || true)

  local count
  if [[ -n "${family_types}" ]]; then
    count=$(echo "${family_types}" | wc -l | tr -d ' ')
  else
    count=0
  fi

  echo "  ${family} family count: ${count}"

  if [[ "${count}" -gt 0 ]]; then
    echo "${family_types}" | sed 's/^/    - /'
  fi
}

wait_for_opt_in() {
  local region="$1"
  local local_zone="$2"

  local max_attempts=18
  local attempt=1
  local status=""

  while [[ "${attempt}" -le "${max_attempts}" ]]; do
    status=$(get_zone_opt_in_status "${region}" "${local_zone}")

    if [[ "${status}" == "opted-in" || "${status}" == "opt-in-not-required" ]]; then
      return 0
    fi

    echo "  Waiting for ${local_zone}. Attempt ${attempt}/${max_attempts}. Current status: ${status}"
    sleep 10

    attempt=$((attempt + 1))
  done

  return 1
}

echo
echo "Cisco Catalyst 8000V Local Zone EC2 Instance Type Check"
echo "======================================================="
echo

if [[ "${ENABLE_LOCAL_ZONES}" == "true" ]]; then
  echo "Mode: ENABLE all scanned Local Zones first, then check support"
else
  echo "Mode: CHECK ONLY, no changes will be made"
fi

echo

enabled_count=0
already_enabled_count=0
enable_error_count=0

# ------------------------------------------------------------
# Phase 1: Enable all scanned Local Zones first
# ------------------------------------------------------------

if [[ "${ENABLE_LOCAL_ZONES}" == "true" ]]; then
  echo "Phase 1: Local Zone Enablement"
  echo "=============================="
  echo

  for entry in "${LOCAL_ZONES[@]}"; do
    IFS="|" read -r friendly_name region local_zone <<< "${entry}"

    echo "Local Zone: ${friendly_name}"
    echo "Region:     ${region}"
    echo "Zone Name:  ${local_zone}"

    zone_status_raw=$(get_zone_status_raw "${region}" "${local_zone}")
    opt_in_status=$(get_zone_opt_in_status "${region}" "${local_zone}")
    group_name=$(get_zone_group_name "${region}" "${local_zone}")

    if [[ -z "${zone_status_raw}" || "${zone_status_raw}" == "None"* ]]; then
      echo "  ERROR: Zone not visible or invalid zone name"
      enable_error_count=$((enable_error_count + 1))
      echo
      continue
    fi

    echo "  Current Status: ${opt_in_status}"
    echo "  Group Name:     ${group_name}"

    if [[ "${opt_in_status}" == "opted-in" || "${opt_in_status}" == "opt-in-not-required" ]]; then
      echo "  ACTION: Already enabled"
      already_enabled_count=$((already_enabled_count + 1))
      echo
      continue
    fi

    if [[ "${opt_in_status}" == "not-opted-in" ]]; then
      echo "  ACTION: Enabling Local Zone group..."

      if enable_local_zone_group "${region}" "${group_name}"; then
        echo "  Enable request submitted."
        enabled_count=$((enabled_count + 1))
      else
        echo "  ERROR: Enable request failed."
        enable_error_count=$((enable_error_count + 1))
      fi

      echo
      continue
    fi

    echo "  WARNING: Unexpected opt-in status: ${opt_in_status}"
    enable_error_count=$((enable_error_count + 1))
    echo
  done

  echo "Enablement Summary"
  echo "=================="
  echo "Newly enabled requests submitted: ${enabled_count}"
  echo "Already enabled:                   ${already_enabled_count}"
  echo "Enablement errors/warnings:         ${enable_error_count}"
  echo

  echo "Waiting for enabled Local Zones to report opted-in..."
  echo

  for entry in "${LOCAL_ZONES[@]}"; do
    IFS="|" read -r friendly_name region local_zone <<< "${entry}"

    opt_in_status=$(get_zone_opt_in_status "${region}" "${local_zone}")

    if [[ "${opt_in_status}" == "opted-in" || "${opt_in_status}" == "opt-in-not-required" ]]; then
      echo "  ${friendly_name}: ${opt_in_status}"
      continue
    fi

    echo "  ${friendly_name}: waiting..."
    if wait_for_opt_in "${region}" "${local_zone}"; then
      echo "  ${friendly_name}: opted-in"
    else
      echo "  ${friendly_name}: still not opted-in"
    fi
  done

  echo
fi

# ------------------------------------------------------------
# Phase 2: Check EC2 instance support
# ------------------------------------------------------------

echo "Phase 2: Cisco Catalyst 8000V EC2 Support Check"
echo "==============================================="
echo

checked_count=0
skipped_not_opted_in=0
candidate_count=0
unsupported_count=0
error_count=0

for entry in "${LOCAL_ZONES[@]}"; do
  IFS="|" read -r friendly_name region local_zone <<< "${entry}"

  echo "Local Zone: ${friendly_name}"
  echo "Region:     ${region}"
  echo "Zone Name:  ${local_zone}"
  echo "-------------------------------------------------------"

  zone_status_raw=$(get_zone_status_raw "${region}" "${local_zone}")
  opt_in_status=$(get_zone_opt_in_status "${region}" "${local_zone}")
  group_name=$(get_zone_group_name "${region}" "${local_zone}")

  if [[ -z "${zone_status_raw}" || "${zone_status_raw}" == "None"* ]]; then
    echo "Zone Status: ERROR - Zone not visible or invalid zone name"
    echo "RESULT: Could not validate this Local Zone."
    error_count=$((error_count + 1))
    echo
    continue
  fi

  echo "Zone Details:"
  echo "  ${zone_status_raw}"
  echo "Group Name:"
  echo "  ${group_name}"
  echo

  if [[ "${opt_in_status}" == "not-opted-in" ]]; then
    echo "RESULT: SKIPPED - Local Zone is not opted in."
    skipped_not_opted_in=$((skipped_not_opted_in + 1))
    echo
    continue
  fi

  if [[ "${opt_in_status}" != "opted-in" && "${opt_in_status}" != "opt-in-not-required" ]]; then
    echo "RESULT: SKIPPED - Unexpected opt-in status: ${opt_in_status}"
    error_count=$((error_count + 1))
    echo
    continue
  fi

  checked_count=$((checked_count + 1))

  echo "Checking EC2 instance type offerings..."
  echo

  all_types=$(get_all_instance_types_in_zone "${region}" "${local_zone}")

  if [[ -z "${all_types}" ]]; then
    echo "Total EC2 instance types offered in this Local Zone: 0"
    echo
    echo "RESULT: WARNING - Local Zone is opted in, but no EC2 instance offerings were returned."
    echo "Possible causes:"
    echo "  - Opt-in is still propagating"
    echo "  - AWS account restrictions"
    echo "  - Temporary capacity/API issue"
    echo "  - Incorrect zone/region mapping"
    error_count=$((error_count + 1))
    echo
    continue
  fi

  total_count=$(echo "${all_types}" | wc -l | tr -d ' ')
  echo "Total EC2 instance types offered in this Local Zone: ${total_count}"
  echo

  echo "Family inventory:"
  for family in "${FAMILIES[@]}"; do
    print_family_inventory "${all_types}" "${family}"
  done

  echo
  echo "Cisco Catalyst 8000V exact instance type support check:"

  option_a_found=$(check_supported_types "${all_types}" "${OPTION_A_TYPES[@]}")
  option_b_found=$(check_supported_types "${all_types}" "${OPTION_B_TYPES[@]}")
  option_c_found=$(check_supported_types "${all_types}" "${OPTION_C_TYPES[@]}")

  print_supported_result "Option A - Preferred C6in" "${option_a_found}"
  print_supported_result "Option B - C5/C5n" "${option_b_found}"
  print_supported_result "Option C - t3.medium demo/test" "${option_c_found}"

  echo

  if [[ -n "${option_a_found}${option_b_found}${option_c_found}" ]]; then
    echo "RESULT: CANDIDATE - Exact Cisco Catalyst 8000V-supported EC2 type found."
    candidate_count=$((candidate_count + 1))
  else
    echo "RESULT: CHECKED BUT NOT SUPPORTED - EC2 exists, but no exact Cisco-supported C8000V instance type was found."
    unsupported_count=$((unsupported_count + 1))
  fi

  echo
done

echo "Final Summary"
echo "============="
echo "Local Zones checked for EC2 offerings:       ${checked_count}"
echo "Local Zones skipped because not opted in:    ${skipped_not_opted_in}"
echo "Candidate Local Zones for Catalyst 8000V:    ${candidate_count}"
echo "Checked but unsupported Local Zones:         ${unsupported_count}"
echo "Errors or warnings:                          ${error_count}"
echo

if [[ "${candidate_count}" -gt 0 ]]; then
  echo "Final Result: At least one Local Zone supports an exact Cisco Catalyst 8000V EC2 instance type."
else
  echo "Final Result: No Cisco Catalyst 8000V-supported EC2 instance types were found in the checked Local Zones."
fi
