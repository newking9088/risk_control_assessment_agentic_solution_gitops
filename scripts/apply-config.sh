#!/usr/bin/env bash
# =============================================================================
# apply-config.sh — Substitute config.yaml values into all template files
# =============================================================================
# Usage:
#   bash scripts/apply-config.sh
#
# What it does:
#   1. Reads config.yaml and exports all KEY: "VALUE" pairs as env vars
#   2. Runs envsubst on every *.tpl file under deployments/values/
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

# Parse config.yaml into env vars (handles  KEY: "value"  and  KEY: value)
while IFS= read -r line; do
  # Skip comments and blank lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue

  key=$(echo "$line" | cut -d':' -f1 | xargs)
  val=$(echo "$line" | cut -d':' -f2- | xargs | sed 's/^"//;s/"$//')

  [[ -z "$key" ]] && continue
  export "$key=$val"
  echo "  $key = $val"
done < "$CONFIG"

echo ""
echo "Substituting values into template files..."

find "$ROOT/deployments/values" -name "*.tpl" | while read -r tpl; do
  out="${tpl%.tpl}"
  envsubst < "$tpl" > "$out"
  echo "  [OK] $out"
done

echo ""
echo "Done. Review the generated files before committing:"
find "$ROOT/deployments/values" -name "*.yaml" ! -name "*.tpl" | sort
