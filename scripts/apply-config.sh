#!/usr/bin/env bash
# =============================================================================
# apply-config.sh — Substitute config.yaml values into all template files
# =============================================================================
# Usage:
#   bash scripts/apply-config.sh
#
# What it does:
#   1. Reads config.yaml and exports all KEY: "VALUE" pairs as env vars
#   2. Runs envsubst on every *.tpl file under deployments/values/,
#      deployments/appset/, and .github/workflows/
#   3. Writes the result alongside the .tpl (strips the .tpl suffix)
#
# Requirements: envsubst (part of gettext — brew install gettext on Mac,
#               apt install gettext on Linux, winget install GNU.gettext on Win)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$ROOT/config.yaml"

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: config.yaml not found at $ROOT/config.yaml"
  exit 1
fi

echo "Reading config.yaml..."

EXPORTED_KEYS=()

# Parse config.yaml into env vars (handles  KEY: "value"  and  KEY: value)
# Inline # comments (preceded by whitespace, outside quotes) are stripped.
while IFS= read -r line; do
  # Skip comment lines and blank lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  # Skip lines without a colon
  [[ "$line" != *:* ]] && continue

  key=$(echo "$line" | cut -d':' -f1 | xargs)
  # Strip trailing inline comment (one or more spaces + # + rest), trim, remove surrounding quotes
  val=$(echo "$line" | cut -d':' -f2- | sed 's/[[:space:]]\{1,\}#.*//' | xargs | sed 's/^"//;s/"$//')

  [[ -z "$key" ]] && continue
  export "$key=$val"
  EXPORTED_KEYS+=("$key")
  echo "  $key = $val"
done < "$CONFIG"

# Sanity check: warn if any exported value contains '#' or unbalanced quotes
echo ""
echo "Validating parsed values..."
for k in "${EXPORTED_KEYS[@]}"; do
  v="${!k}"
  if [[ "$v" == *'#'* ]]; then
    echo "  WARN: $k value contains '#' — possible unparsed comment: $v"
  fi
  dq="${v//[^\"]/}"
  sq="${v//[^\']/}"
  if (( ${#dq} % 2 != 0 )) || (( ${#sq} % 2 != 0 )); then
    echo "  WARN: $k value may have unbalanced quotes: $v"
  fi
done

echo ""
echo "Substituting values into template files..."

find "$ROOT/deployments/values" "$ROOT/deployments/appset" "$ROOT/.github/workflows" -name "*.tpl" | while read -r tpl; do
  out="${tpl%.tpl}"
  case "$tpl" in
    "$ROOT/.github/workflows/"*)
      # Only substitute identity vars; leave ${{ }} GitHub Actions expressions untouched
      envsubst '${APP_NAME} ${GITHUB_ORG} ${GITHUB_REPO}' < "$tpl" > "$out"
      ;;
    *)
      envsubst < "$tpl" > "$out"
      ;;
  esac
  echo "  [OK] $out"
done

echo ""
echo "Done. Review the generated files before committing:"
find "$ROOT/deployments/values" "$ROOT/deployments/appset" "$ROOT/.github/workflows" \
  -name "*.yaml" ! -name "*.tpl" | sort
