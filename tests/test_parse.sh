#!/usr/bin/env bash
# Unit tests for the config.yaml parsing logic in scripts/apply-config.sh.
# Tests the core parse_val pipeline in isolation — no file I/O, no side effects.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib.sh"

# Replicate the exact parse pipeline from apply-config.sh
parse_val() {
  echo "$1" | cut -d':' -f2- | sed 's/[[:space:]]\{1,\}#.*//' | xargs | sed 's/^"//;s/"$//'
}

parse_key() {
  echo "$1" | cut -d':' -f1 | xargs
}

echo "--- config.yaml parsing unit tests ---"

# Basic quoted value
assert_eq "quoted value" \
  "my-test-app" \
  "$(parse_val 'APP_NAME: "my-test-app"')"

# Unquoted value
assert_eq "unquoted value" \
  "8000" \
  "$(parse_val 'API_PORT: 8000')"

# Inline comment after quoted value (Fix 2 target)
assert_eq "inline comment stripped from quoted value" \
  "test-kv-dev" \
  "$(parse_val 'KEYVAULT_NAME_DEV: "test-kv-dev"     # used for dev + qa')"

# Inline comment after unquoted value
assert_eq "inline comment stripped from unquoted value" \
  "ubuntu-latest" \
  "$(parse_val 'CI_RUNNER: ubuntu-latest    # default runner')"

# Empty quoted value
assert_eq "empty quoted value" \
  "" \
  "$(parse_val 'CI_REUSABLE_WORKFLOW_REF: ""')"

# URL with multiple colons — cut -d':' -f2- must preserve the full URL
assert_eq "URL value with multiple colons preserved" \
  "https://api.openai.com" \
  "$(parse_val 'LLM_API_URL: "https://api.openai.com"')"

# Key extraction
assert_eq "key extracted from standard line" \
  "APP_NAME" \
  "$(parse_key 'APP_NAME: "my-test-app"')"

assert_eq "key extracted with leading spaces" \
  "DOMAIN_SUFFIX" \
  "$(parse_key '  DOMAIN_SUFFIX: "apps.example.com"')"

# Sanity check logic: value with # triggers warning
assert_contains "sanity check detects # in value" \
  "WARN" \
  "$(v='value # with hash'; [[ "$v" == *'#'* ]] && echo 'WARN detected')"

# Sanity check logic: clean value produces no warning
assert_not_contains "sanity check silent for clean value" \
  "WARN" \
  "$(v='clean-value'; [[ "$v" == *'#'* ]] && echo 'WARN detected' || echo 'OK')"

# Sanity check logic: unbalanced double quote triggers warning
assert_contains "sanity check detects unbalanced double quote" \
  "WARN" \
  "$(v='bad\"val'; dq="${v//[^\"]/}"; (( ${#dq} % 2 != 0 )) && echo 'WARN detected' || echo 'OK')"

report
