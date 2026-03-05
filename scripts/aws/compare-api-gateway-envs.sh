#!/usr/bin/env bash
# @description Compare API Gateway configuration between two environments
#
# Compare API Gateway configuration between two environments (e.g. stage vs prod).
# Use this to verify both environments are configured the same way, especially
# for the redirect-form endpoint (302 + Location header).
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - You need the REST API ID for each environment (see "How to get API IDs" below)
#
# When run interactively, the script prompts for:
#   1) Export folder for API definitions (default: /tmp/api-gateway-compare)
#   2) AWS profile (if AWS_PROFILE is not set), listing profiles from ~/.aws
#
# Usage:
#   ./scripts/compare-api-gateway-envs.sh <rest-api-id-env1> <rest-api-id-env2> [stage-name]
#
# Example (stage vs prod, default stage name "stage"):
#   ./scripts/compare-api-gateway-envs.sh abc123xyz stage-api-id def456uvw prod-api-id
#
# Example with explicit stage names:
#   REST_API_ID_GOOD=xxx REST_API_ID_BAD=yyy STAGE=stage ./scripts/compare-api-gateway-envs.sh
#
# How to get REST API IDs:
#   - AWS Console: API Gateway → APIs → your API → API ID in the dashboard.
#   - CLI: aws apigateway get-rest-apis --query "items[?name=='your-api-name'].id" --output text
#   - Or from the invoke URL: https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/
#

set -e

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

# Prompt user to choose an AWS profile when not set (and stdin is a TTY)
prompt_aws_profile() {
  [ -n "$AWS_PROFILE" ] && return 0
  [ ! -t 0 ] && return 0
  local profiles
  profiles=($(list_aws_profiles))
  [ ${#profiles[@]} -eq 0 ] && return 0
  echo "Available AWS profiles:"
  local i=1 n num_default
  n=${#profiles[@]}
  for p in "${profiles[@]}"; do
    echo "  $i) $p"
    i=$((i + 1))
  done
  num_default=$i
  echo "  $num_default) (default — no profile)"
  echo ""
  local choice
  read -r -p "Select profile number [1]: " choice
  choice="${choice:-1}"
  if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -lt "$num_default" ]; then
    export AWS_PROFILE="${profiles[$((choice-1))]}"
    echo "Using profile: $AWS_PROFILE"
  elif [ "$choice" -eq "$num_default" ] 2>/dev/null; then
    echo "Using default (no profile)."
  else
    export AWS_PROFILE="${profiles[0]}"
    echo "Using profile: $AWS_PROFILE"
  fi
  echo ""
}

# Allow passing API IDs as env vars or as first two positional args
REST_API_ID_1="${REST_API_ID_1:-$1}"
REST_API_ID_2="${REST_API_ID_2:-$2}"
STAGE_NAME="${STAGE_NAME:-${3:-stage}}"
REGION="${AWS_REGION:-eu-west-1}"

if [ -z "$REST_API_ID_1" ] || [ -z "$REST_API_ID_2" ]; then
  echo "Usage: $0 <rest-api-id-env1> <rest-api-id-env2> [stage-name]"
  echo "   or: REST_API_ID_1=id1 REST_API_ID_2=id2 [STAGE_NAME=stage] $0"
  echo ""
  echo "Exports both APIs (with integrations) and diffs them."
  exit 1
fi

prompt_export_folder
prompt_aws_profile
AWS_PROFILE="${AWS_PROFILE:-}"

CLI="aws apigateway"
[ -n "$AWS_PROFILE" ] && CLI="aws apigateway --profile $AWS_PROFILE"
CLI="$CLI --region $REGION"

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
  # get-export writes the export body to the given file; disable pager so stdout is not used
  AWS_CLI_AUTO_PROMPT=off AWS_PAGER="" $CLI get-export \
    --rest-api-id "$api_id" \
    --stage-name "$STAGE_NAME" \
    --export-type oas30 \
    --parameters "$EXPORT_OPTS" \
    --accepts application/json \
    "$out_file" 2>/dev/null && validate_export "$out_file" "$label" && return 0
  echo "  (retry without stage)"
  AWS_PAGER="" $CLI get-export \
    --rest-api-id "$api_id" \
    --export-type oas30 \
    --parameters "$EXPORT_OPTS" \
    --accepts application/json \
    "$out_file" 2>/dev/null && validate_export "$out_file" "$label"
}

echo "Exporting API 1 (env1): $REST_API_ID_1"
export_api "$REST_API_ID_1" "$OUT_DIR/env1-${REST_API_ID_1}.json" "env1" || true

echo "Exporting API 2 (env2): $REST_API_ID_2"
export_api "$REST_API_ID_2" "$OUT_DIR/env2-${REST_API_ID_2}.json" "env2" || true

echo ""
FILE1="$OUT_DIR/env1-${REST_API_ID_1}.json"
FILE2="$OUT_DIR/env2-${REST_API_ID_2}.json"
if [ -f "$FILE1" ] && [ -f "$FILE2" ] && [ "$(wc -c < "$FILE1" | tr -d ' ')" -ge 200 ] && [ "$(wc -c < "$FILE2" | tr -d ' ')" -ge 200 ]; then
  echo "--- Diff (env1 vs env2) ---"
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
echo "  - env1: $OUT_DIR_ABS/env1-${REST_API_ID_1}.json"
echo "  - env2: $OUT_DIR_ABS/env2-${REST_API_ID_2}.json"
echo "Search for 'redirect-form', '302', 'Location', 'integration' in both files to compare."
