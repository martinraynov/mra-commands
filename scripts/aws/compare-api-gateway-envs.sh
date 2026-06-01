#!/usr/bin/env bash
# @description Compare API Gateway configuration between two environments
#
# Compare API Gateway configuration between two environments (e.g. stage vs prod).
# Use this to verify both environments are configured the same way.
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - You need the REST API ID for each environment (see "How to get API IDs" below)
#
# When run interactively, the script prompts for:
#   1) Environment for each comparison input (from API_GATEWAY_CONFIG_*_ENVS below)
#   2) Export folder for API definitions (default: /tmp/api-gateway-compare)
#   3) AWS profile per comparison input (unless AWS_PROFILE_1 / AWS_PROFILE_2 are set)
#   4) API Gateway stage per input (listed from AWS; invalid defaults are replaced)
#
# Usage:
#   ./scripts/aws/compare-api-gateway-envs.sh
#   ./scripts/aws/compare-api-gateway-envs.sh <rest-api-id-env1> <rest-api-id-env2> [stage-name]
#
# Example (non-interactive, stage vs prod):
#   ./scripts/aws/compare-api-gateway-envs.sh abc123xyz def456uvw stage
#
# Example with env vars (skips prompts):
#   REST_API_ID_1=xxx REST_API_ID_2=yyy \
#   AWS_PROFILE_1=wdpr-integration AWS_PROFILE_2=wdpr-production \
#   REGION_1=eu-west-1 REGION_2=eu-west-1 \
#   STAGE_NAME_1=latest STAGE_NAME_2=latest ./scripts/aws/compare-api-gateway-envs.sh
#
# How to get REST API IDs:
#   - AWS Console: API Gateway → APIs → your API → API ID in the dashboard.
#   - CLI: aws apigateway get-rest-apis --query "items[?name=='your-api-name'].id" --output text
#   - Or from the invoke URL: https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/
#

set -e

# --- API Gateway comparison inputs (edit for your APIs) ---
# Each comparison input has a label and a list of environments.
# Environment entry format: "env_label|rest_api_id|stage_name[|aws_profile]"
#
# When REST_API_ID_1 / REST_API_ID_2 are not set on the command line, the script
# prompts you to pick an environment from the matching list below.

API_GATEWAY_CONFIG_1_NAME="API Gateway (input 1)"
API_GATEWAY_CONFIG_1_ENVS=(
  "stage|REPLACE_WITH_STAGE_REST_API_ID|stage"
  "prod|REPLACE_WITH_PROD_REST_API_ID|prod"
)

API_GATEWAY_CONFIG_2_NAME="API Gateway (input 2)"
API_GATEWAY_CONFIG_2_ENVS=(
  "stage|REPLACE_WITH_STAGE_REST_API_ID|stage"
  "prod|REPLACE_WITH_PROD_REST_API_ID|prod"
)

# List available AWS profiles (from ~/.aws/credentials and ~/.aws/config)
list_aws_profiles() {
  if aws configure list-profiles 2>/dev/null; then
    return
  fi
  # Fallback: parse [profile x] from config and [x] from credentials
  for f in "${HOME}/.aws/config" "${HOME}/.aws/credentials"; do
    [ -f "$f" ] && awk -F'[][]' '/^\[/ && $2 != "" { gsub(/^profile /, "", $2); print $2 }' "$f" 2>/dev/null
  done | sort -u
}

# Default export folder (used by prompt and when OUT_DIR is not set)
DEFAULT_EXPORT_DIR="/tmp/api-gateway-compare"

# Prompt for export folder when run interactively (before AWS profile prompt)
prompt_export_folder() {
  [ ! -t 0 ] && return 0
  local dir
  read -r -p "Export folder for API definitions [$DEFAULT_EXPORT_DIR]: " dir
  export OUT_DIR="${dir:-$DEFAULT_EXPORT_DIR}"
  echo "Using export folder: $OUT_DIR"
  echo ""
}

# Cached profile list for repeated prompts
_AWS_PROFILES=()

load_aws_profiles() {
  [ ${#_AWS_PROFILES[@]} -gt 0 ] && return 0
  _AWS_PROFILES=($(list_aws_profiles))
}

# Prompt user to choose an AWS profile for one comparison input.
# Sets AWS_PROFILE_1 or AWS_PROFILE_2 (empty string = default credentials).
prompt_aws_profile_for_input() {
  local side="$1"
  local env_label="$2"
  local api_id="$3"
  local current=""

  if [ "$side" = "1" ]; then
    current="${AWS_PROFILE_1:-}"
  else
    current="${AWS_PROFILE_2:-}"
  fi
  [ -n "$current" ] && return 0
  [ ! -t 0 ] && return 0

  load_aws_profiles
  [ ${#_AWS_PROFILES[@]} -eq 0 ] && return 0

  echo "Select AWS profile for input $side — $env_label (API: $api_id):"
  local i=1 n num_default
  n=${#_AWS_PROFILES[@]}
  local p
  for p in "${_AWS_PROFILES[@]}"; do
    echo "  $i) $p"
    i=$((i + 1))
  done
  num_default=$i
  echo "  $num_default) (default — no profile)"
  echo ""
  local choice selected=""
  read -r -p "Select profile number [1]: " choice
  choice="${choice:-1}"
  if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -lt "$num_default" ]; then
    selected="${_AWS_PROFILES[$((choice - 1))]}"
  elif [ "$choice" -eq "$num_default" ] 2>/dev/null; then
    selected=""
  else
    selected="${_AWS_PROFILES[0]}"
  fi

  if [ "$side" = "1" ]; then
    AWS_PROFILE_1="$selected"
  else
    AWS_PROFILE_2="$selected"
  fi
  if [ -n "$selected" ]; then
    echo "Using profile for input $side: $selected"
  else
    echo "Using default credentials for input $side (no profile)."
  fi
  echo ""
}

# Parse "env_label|rest_api_id|stage_name[|aws_profile]" into named variables.
parse_api_gateway_env_entry() {
  local entry="$1"
  _PARSED_AWS_PROFILE=""
  IFS='|' read -r _PARSED_ENV_LABEL _PARSED_REST_API_ID _PARSED_STAGE_NAME _PARSED_AWS_PROFILE <<< "$entry"
}

# Prompt to pick an environment from a configured API Gateway input.
# Sets REST_API_ID_* , STAGE_NAME_* , and ENV_LABEL_* for the chosen side.
prompt_api_gateway_env() {
  local side="$1"
  local config_name="$2"
  shift 2
  local -a env_entries=("$@")

  [ ! -t 0 ] && return 0
  [ ${#env_entries[@]} -eq 0 ] && return 0

  local valid_entries=()
  local entry env_label rest_api_id stage_name
  for entry in "${env_entries[@]}"; do
    parse_api_gateway_env_entry "$entry"
    env_label="$_PARSED_ENV_LABEL"
    rest_api_id="$_PARSED_REST_API_ID"
    stage_name="$_PARSED_STAGE_NAME"
    [ -z "$env_label" ] || [ -z "$rest_api_id" ] || [ -z "$stage_name" ] && continue
    case "$rest_api_id" in
      REPLACE_WITH_*|"") continue ;;
    esac
    valid_entries+=("$entry")
  done

  if [ ${#valid_entries[@]} -eq 0 ]; then
    echo "No environments configured for $config_name (edit API_GATEWAY_CONFIG_${side}_ENVS in this script)."
    return 0
  fi

  echo "Select environment for comparison input $side — $config_name:"
  local i=1 choice
  for entry in "${valid_entries[@]}"; do
    parse_api_gateway_env_entry "$entry"
    echo "  $i) $_PARSED_ENV_LABEL (API: $_PARSED_REST_API_ID, stage: $_PARSED_STAGE_NAME)"
    i=$((i + 1))
  done
  echo ""
  read -r -p "Select environment number [1]: " choice
  choice="${choice:-1}"
  if ! [ "$choice" -ge 1 ] 2>/dev/null || [ "$choice" -gt ${#valid_entries[@]} ]; then
    choice=1
  fi
  parse_api_gateway_env_entry "${valid_entries[$((choice - 1))]}"
  if [ "$side" = "1" ]; then
    REST_API_ID_1="$_PARSED_REST_API_ID"
    STAGE_NAME_1="$_PARSED_STAGE_NAME"
    ENV_LABEL_1="$_PARSED_ENV_LABEL"
    [ -n "$_PARSED_AWS_PROFILE" ] && AWS_PROFILE_1="$_PARSED_AWS_PROFILE"
  else
    REST_API_ID_2="$_PARSED_REST_API_ID"
    STAGE_NAME_2="$_PARSED_STAGE_NAME"
    ENV_LABEL_2="$_PARSED_ENV_LABEL"
    [ -n "$_PARSED_AWS_PROFILE" ] && AWS_PROFILE_2="$_PARSED_AWS_PROFILE"
  fi
  echo "Using input $side: $_PARSED_ENV_LABEL (API $_PARSED_REST_API_ID, stage $_PARSED_STAGE_NAME)"
  [ -n "$_PARSED_AWS_PROFILE" ] && echo "  Profile from config: $_PARSED_AWS_PROFILE"
  echo ""
}

# Allow passing API IDs as env vars or as first two positional args
REST_API_ID_1="${REST_API_ID_1:-$1}"
REST_API_ID_2="${REST_API_ID_2:-$2}"
STAGE_NAME="${STAGE_NAME:-${3:-}}"
STAGE_NAME_1="${STAGE_NAME_1:-$STAGE_NAME}"
STAGE_NAME_2="${STAGE_NAME_2:-$STAGE_NAME}"
ENV_LABEL_1="${ENV_LABEL_1:-input-1}"
ENV_LABEL_2="${ENV_LABEL_2:-input-2}"
AWS_PROFILE_1="${AWS_PROFILE_1:-}"
AWS_PROFILE_2="${AWS_PROFILE_2:-}"
REGION_1="${REGION_1:-}"
REGION_2="${REGION_2:-}"
API_GW_TYPE_1="${API_GW_TYPE_1:-rest}"
API_GW_TYPE_2="${API_GW_TYPE_2:-rest}"

# Regions scanned when the API is not found in the profile default region
_DISCOVER_REGIONS=(eu-west-1 eu-central-1 us-east-1 us-west-2)

aws_region_for_profile() {
  local profile="$1"
  local region=""
  if [ -n "$profile" ]; then
    region=$(aws configure get region --profile "$profile" 2>/dev/null || true)
  else
    region=$(aws configure get region 2>/dev/null || true)
  fi
  printf '%s' "${region:-${AWS_REGION:-eu-west-1}}"
}

apigateway_cli() {
  local profile="$1"
  local region="$2"
  local cli="aws apigateway"
  [ -n "$profile" ] && cli="$cli --profile $profile"
  echo "$cli --region $region"
}

apigatewayv2_cli() {
  local profile="$1"
  local region="$2"
  local cli="aws apigatewayv2"
  [ -n "$profile" ] && cli="$cli --profile $profile"
  echo "$cli --region $region"
}

region_for_side() {
  if [ "$1" = "1" ]; then echo "$REGION_1"; else echo "$REGION_2"; fi
}

api_gw_type_for_side() {
  if [ "$1" = "1" ]; then echo "$API_GW_TYPE_1"; else echo "$API_GW_TYPE_2"; fi
}

set_region_for_side() {
  if [ "$1" = "1" ]; then REGION_1="$2"; else REGION_2="$2"; fi
}

set_api_gw_type_for_side() {
  if [ "$1" = "1" ]; then API_GW_TYPE_1="$2"; else API_GW_TYPE_2="$2"; fi
}

rest_api_exists() {
  local api_id="$1" profile="$2" region="$3"
  local -a args=(apigateway get-rest-api --rest-api-id "$api_id" --region "$region")
  [ -n "$profile" ] && args+=(--profile "$profile")
  AWS_PAGER="" aws "${args[@]}" &>/dev/null
}

v2_api_exists() {
  local api_id="$1" profile="$2" region="$3"
  local -a args=(apigatewayv2 get-api --api-id "$api_id" --region "$region")
  [ -n "$profile" ] && args+=(--profile "$profile")
  AWS_PAGER="" aws "${args[@]}" &>/dev/null
}

# Prints "rest:region" or "v2:region" on success.
discover_api_region() {
  local api_id="$1" profile="$2"
  local -a try_regions=()
  local r seen="" region

  region=$(aws_region_for_profile "$profile")
  try_regions=("$region" "${AWS_REGION:-}" "${_DISCOVER_REGIONS[@]}")

  for r in "${try_regions[@]}"; do
    [ -z "$r" ] && continue
    case " $seen " in *" $r "*) continue ;; esac
    seen="$seen $r"
    if rest_api_exists "$api_id" "$profile" "$r"; then
      printf 'rest:%s' "$r"
      return 0
    fi
    if v2_api_exists "$api_id" "$profile" "$r"; then
      printf 'v2:%s' "$r"
      return 0
    fi
  done
  return 1
}

# Sets REGION_* and API_GW_TYPE_* for one input.
resolve_input_region() {
  local side="$1" profile="$2" api_id="$3"
  local region type found

  region="$(region_for_side "$side")"
  type="$(api_gw_type_for_side "$side")"

  if [ -n "$region" ]; then
    if [ "$type" = "v2" ] && v2_api_exists "$api_id" "$profile" "$region"; then
      echo "Input $side: HTTP API (v2) in $region"
      return 0
    fi
    if [ "$type" != "v2" ] && rest_api_exists "$api_id" "$profile" "$region"; then
      set_api_gw_type_for_side "$side" "rest"
      echo "Input $side: REST API in $region"
      return 0
    fi
    echo "Input $side: API not found in configured region $region; searching other regions..."
  fi

  region=$(aws_region_for_profile "$profile")
  if rest_api_exists "$api_id" "$profile" "$region"; then
    set_region_for_side "$side" "$region"
    set_api_gw_type_for_side "$side" "rest"
    echo "Input $side: REST API in $region"
    return 0
  fi
  if v2_api_exists "$api_id" "$profile" "$region"; then
    set_region_for_side "$side" "$region"
    set_api_gw_type_for_side "$side" "v2"
    echo "Input $side: HTTP API (v2) in $region"
    return 0
  fi

  found=$(discover_api_region "$api_id" "$profile") || return 1
  type="${found%%:*}"
  region="${found#*:}"
  set_region_for_side "$side" "$region"
  set_api_gw_type_for_side "$side" "$type"
  if [ "$type" = "v2" ]; then
    echo "Input $side: HTTP API (v2) in $region"
  else
    echo "Input $side: REST API in $region"
  fi
}

stage_name_for_side() {
  if [ "$1" = "1" ]; then echo "$STAGE_NAME_1"; else echo "$STAGE_NAME_2"; fi
}

set_stage_name_for_side() {
  if [ "$1" = "1" ]; then STAGE_NAME_1="$2"; else STAGE_NAME_2="$2"; fi
}

# List deployment stage names (stdout). Errors go to stderr.
# Exit 0 = stages listed, 1 = AWS error, 2 = success but no stages.
list_api_gateway_stages() {
  local api_id="$1" profile="$2" region="$3" api_type="$4"
  local cli err_file out rc

  err_file="$(mktemp "${TMPDIR:-/tmp}/apigw-stages-err.XXXXXX")"
  if [ "$api_type" = "v2" ]; then
    cli="$(apigatewayv2_cli "$profile" "$region")"
    out=$(AWS_PAGER="" $cli get-stages --api-id "$api_id" \
      --query 'Items[*].StageName' --output text 2>"$err_file")
  else
    cli="$(apigateway_cli "$profile" "$region")"
    out=$(AWS_PAGER="" $cli get-stages --rest-api-id "$api_id" \
      --query 'item[*].stageName' --output text 2>"$err_file")
  fi
  rc=$?

  if [ $rc -ne 0 ]; then
    echo "AWS error listing stages:" >&2
    [ -s "$err_file" ] && sed 's/^/  /' "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi
  rm -f "$err_file"

  if [ -z "$out" ] || [ "$out" = "None" ]; then
    return 2
  fi
  printf '%s\n' "$out" | tr '\t' '\n' | sed '/^$/d' | sort -u
  return 0
}

stage_exists_in_list() {
  local want="$1"
  shift
  local s
  for s in "$@"; do
    [ "$s" = "$want" ] && return 0
  done
  return 1
}

prompt_manual_stage_name() {
  local side="$1"
  local name=""
  [ ! -t 0 ] && return 1
  read -r -p "Enter stage name for input $side: " name
  [ -z "$name" ] && return 1
  set_stage_name_for_side "$side" "$name"
  echo "Using stage for input $side: $name"
  echo ""
  return 0
}

# Resolve STAGE_NAME_* via AWS (prompt if needed). Requires profile to be set first.
prompt_stage_for_input() {
  local side="$1"
  local env_label="$2"
  local api_id="$3"
  local profile="$4"
  local current stages=() stage_list list_rc region api_type

  resolve_input_region "$side" "$profile" "$api_id" || {
    echo "Could not find API $api_id with profile ${profile:-default}."
    echo "Set REGION_${side} to the correct region, refresh AWS credentials, and retry."
    return 1
  }
  echo ""

  region="$(region_for_side "$side")"
  api_type="$(api_gw_type_for_side "$side")"
  current="$(stage_name_for_side "$side")"

  if [ "$api_type" = "v2" ]; then
    echo "Input $side is HTTP API (v2); no stage required for export."
    echo ""
    return 0
  fi

  set +e
  stage_list=$(list_api_gateway_stages "$api_id" "$profile" "$region" "$api_type")
  list_rc=$?
  set -e

  if [ $list_rc -eq 1 ]; then
    echo "Could not list stages for input $side (API: $api_id, profile: ${profile:-default}, region: $region)."
    if [ -t 0 ] && prompt_manual_stage_name "$side"; then
      return 0
    fi
    return 1
  fi

  if [ $list_rc -eq 2 ]; then
    echo "No stages returned for input $side (API: $api_id, region: $region)."
    if [ -t 0 ] && prompt_manual_stage_name "$side"; then
      return 0
    fi
    return 1
  fi

  while IFS= read -r s; do
    [ -n "$s" ] && stages+=("$s")
  done <<< "$stage_list"

  if [ ${#stages[@]} -eq 0 ]; then
    echo "No stages found for input $side (API: $api_id)."
    if [ -t 0 ] && prompt_manual_stage_name "$side"; then
      return 0
    fi
    return 1
  fi

  if [ -n "$current" ] && stage_exists_in_list "$current" "${stages[@]}"; then
    echo "Using stage for input $side: $current"
    echo ""
    return 0
  fi

  if [ ${#stages[@]} -eq 1 ]; then
    set_stage_name_for_side "$side" "${stages[0]}"
    if [ -n "$current" ] && [ "$current" != "${stages[0]}" ]; then
      echo "Stage '$current' not found for input $side; using '${stages[0]}'."
    else
      echo "Using stage for input $side: ${stages[0]}"
    fi
    echo ""
    return 0
  fi

  if [ ! -t 0 ]; then
    echo "Stage '${current:-<unset>}' is not valid for input $side (API: $api_id)."
    echo "Available stages: ${stages[*]}"
    return 1
  fi

  echo "Select stage for input $side — $env_label (API: $api_id):"
  if [ -n "$current" ]; then
    echo "  (stage '$current' does not exist on this API)"
  fi
  local i=1 choice s
  for s in "${stages[@]}"; do
    echo "  $i) $s"
    i=$((i + 1))
  done
  echo ""
  read -r -p "Select stage number [1]: " choice
  choice="${choice:-1}"
  if ! [ "$choice" -ge 1 ] 2>/dev/null || [ "$choice" -gt ${#stages[@]} ]; then
    choice=1
  fi
  set_stage_name_for_side "$side" "${stages[$((choice - 1))]}"
  echo "Using stage for input $side: $(stage_name_for_side "$side")"
  echo ""
}

if [ -z "$REST_API_ID_1" ]; then
  prompt_api_gateway_env 1 "$API_GATEWAY_CONFIG_1_NAME" "${API_GATEWAY_CONFIG_1_ENVS[@]}"
fi
if [ -z "$REST_API_ID_2" ]; then
  prompt_api_gateway_env 2 "$API_GATEWAY_CONFIG_2_NAME" "${API_GATEWAY_CONFIG_2_ENVS[@]}"
fi

if [ -z "$REST_API_ID_1" ] || [ -z "$REST_API_ID_2" ]; then
  echo "Usage: $0 [<rest-api-id-input-1> <rest-api-id-input-2> [stage-name]]"
  echo "   or: REST_API_ID_1=id1 REST_API_ID_2=id2 AWS_PROFILE_1=p1 AWS_PROFILE_2=p2 $0"
  echo "   or: configure API_GATEWAY_CONFIG_*_ENVS in this script and run interactively."
  echo ""
  echo "Exports both APIs (with integrations) and diffs them."
  exit 1
fi

prompt_export_folder
prompt_aws_profile_for_input 1 "$ENV_LABEL_1" "$REST_API_ID_1"
prompt_aws_profile_for_input 2 "$ENV_LABEL_2" "$REST_API_ID_2"
prompt_stage_for_input 1 "$ENV_LABEL_1" "$REST_API_ID_1" "$AWS_PROFILE_1"
prompt_stage_for_input 2 "$ENV_LABEL_2" "$REST_API_ID_2" "$AWS_PROFILE_2"

# Include x-amazon-apigateway-integration in export so we can compare 302/Location
EXPORT_OPTS="extensions=integrations"
OUT_DIR="${OUT_DIR:-$DEFAULT_EXPORT_DIR}"
mkdir -p "$OUT_DIR"
OUT_DIR_ABS="$(cd "$OUT_DIR" 2>/dev/null && pwd || echo "$OUT_DIR")"
echo "Export directory: $OUT_DIR_ABS"
echo ""

# Validate that the export file contains real OpenAPI (not metadata or error payload)
validate_export() {
  local out_file="$1"
  local label="$2"
  if [ ! -f "$out_file" ]; then
    echo "  FAIL: $label - file not created."
    return 1
  fi
  local size
  size=$(wc -c < "$out_file" | tr -d ' ')
  if [ "$size" -lt 200 ]; then
    echo "  FAIL: $label - file too small (${size} bytes). Content may be metadata/error only."
    head -5 "$out_file"
    return 1
  fi
  if ! grep -q '"openapi"\|\"paths\"' "$out_file" 2>/dev/null; then
    echo "  FAIL: $label - file does not look like OpenAPI (no openapi/paths)."
    head -3 "$out_file"
    return 1
  fi
  echo "  OK: $label - ${size} bytes, valid OpenAPI."
  return 0
}

export_api() {
  local api_id="$1"
  local out_file="$2"
  local label="$3"
  local stage_name="$4"
  local profile="${5:-}"
  local region="$6"
  local api_type="${7:-rest}"
  local cli err_file

  err_file="$(mktemp "${TMPDIR:-/tmp}/apigw-export-err.XXXXXX")"

  if [ "$api_type" = "v2" ]; then
    cli="$(apigatewayv2_cli "$profile" "$region")"
    if AWS_CLI_AUTO_PROMPT=off AWS_PAGER="" $cli export-api \
      --api-id "$api_id" \
      --output-type JSON \
      --specification OAS30 \
      "$out_file" 2>"$err_file" && validate_export "$out_file" "$label"; then
      rm -f "$err_file"
      return 0
    fi
    if [ -s "$err_file" ]; then
      echo "  Export failed (HTTP API v2, profile: ${profile:-default}, region: $region):"
      sed 's/^/    /' "$err_file"
    fi
    rm -f "$err_file"
    return 1
  fi

  [ -n "$stage_name" ] || {
    echo "  FAIL: $label - no stage name (re-run and select a stage)."
    return 1
  }
  cli="$(apigateway_cli "$profile" "$region")"
  # get-export writes the export body to the given file; disable pager so stdout is not used
  if AWS_CLI_AUTO_PROMPT=off AWS_PAGER="" $cli get-export \
    --rest-api-id "$api_id" \
    --stage-name "$stage_name" \
    --export-type oas30 \
    --parameters "$EXPORT_OPTS" \
    --accepts application/json \
    "$out_file" 2>"$err_file" && validate_export "$out_file" "$label"; then
    rm -f "$err_file"
    return 0
  fi
  if [ -s "$err_file" ]; then
    echo "  Export failed (stage: $stage_name, profile: ${profile:-default}, region: $region):"
    sed 's/^/    /' "$err_file"
    if grep -q 'Invalid stage identifier' "$err_file" 2>/dev/null; then
      echo "    Hint: pick a valid stage from the list shown above, or run:"
      echo "      $(apigateway_cli "$profile" "$region") get-stages --rest-api-id $api_id --query 'item[*].stageName' --output table"
    fi
  fi
  rm -f "$err_file"
  return 1
}

slugify_label() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//'
}

SLUG_1="$(slugify_label "$ENV_LABEL_1")"
SLUG_2="$(slugify_label "$ENV_LABEL_2")"

echo "Exporting input 1 ($ENV_LABEL_1): $REST_API_ID_1 (stage: ${STAGE_NAME_1:-n/a}, profile: ${AWS_PROFILE_1:-default}, region: $REGION_1)"
export_api "$REST_API_ID_1" "$OUT_DIR/${SLUG_1}-${REST_API_ID_1}.json" "$ENV_LABEL_1" "$STAGE_NAME_1" "$AWS_PROFILE_1" "$REGION_1" "$API_GW_TYPE_1" || true

echo "Exporting input 2 ($ENV_LABEL_2): $REST_API_ID_2 (stage: ${STAGE_NAME_2:-n/a}, profile: ${AWS_PROFILE_2:-default}, region: $REGION_2)"
export_api "$REST_API_ID_2" "$OUT_DIR/${SLUG_2}-${REST_API_ID_2}.json" "$ENV_LABEL_2" "$STAGE_NAME_2" "$AWS_PROFILE_2" "$REGION_2" "$API_GW_TYPE_2" || true

echo ""
FILE1="$OUT_DIR/${SLUG_1}-${REST_API_ID_1}.json"
FILE2="$OUT_DIR/${SLUG_2}-${REST_API_ID_2}.json"
if [ -f "$FILE1" ] && [ -f "$FILE2" ] && [ "$(wc -c < "$FILE1" | tr -d ' ')" -ge 200 ] && [ "$(wc -c < "$FILE2" | tr -d ' ')" -ge 200 ]; then
  echo "--- Diff ($ENV_LABEL_1 vs $ENV_LABEL_2) ---"
  if command -v diff >/dev/null 2>&1; then
    diff -u "$FILE1" "$FILE2" || true
  else
    echo "Install diff to see changes. Exports saved in $OUT_DIR/"
  fi
else
  echo "Skipping diff: one or both exports failed validation. Fix exports above and re-run."
fi

echo ""
echo "Exported files are stored in: $OUT_DIR_ABS"
echo "  - $ENV_LABEL_1: $OUT_DIR_ABS/${SLUG_1}-${REST_API_ID_1}.json"
echo "  - $ENV_LABEL_2: $OUT_DIR_ABS/${SLUG_2}-${REST_API_ID_2}.json"
echo "Search for 'redirect-form', '302', 'Location', 'integration' in both files to compare."
