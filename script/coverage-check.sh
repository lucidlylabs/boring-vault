#!/usr/bin/env bash
# Search boring-vault for existing decoder/leaf/test coverage for a protocol.
#
# Usage:
#   ./script/coverage-check.sh <search_term>

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERM="${1:-}"

if [[ -z "$TERM" ]]; then
  echo "Usage: ./script/coverage-check.sh <protocol_name_or_address>" >&2
  exit 1
fi

SEARCH="$(echo "$TERM" | tr '[:upper:]' '[:lower:]')"

search_files() {
  local pattern="$1"
  local path="$2"
  if command -v rg >/dev/null; then
    rg -l -i "$pattern" "$path" 2>/dev/null || true
  else
    grep -ril "$pattern" "$path" 2>/dev/null || true
  fi
}

search_content() {
  local pattern="$1"
  local path="$2"
  if command -v rg >/dev/null; then
    rg -i "$pattern" "$path" 2>/dev/null | head -20 || true
  else
    grep -ri "$pattern" "$path" 2>/dev/null | head -20 || true
  fi
}

print_section() {
  local title="$1"
  local results="$2"
  echo "=== ${title} ==="
  if [[ -n "$results" ]]; then
    echo "$results" | sed 's/^/  /'
  else
    echo "  (none)"
  fi
  echo ""
}

print_section "Decoders (Protocols/)" \
  "$(search_files "$SEARCH" "${ROOT}/src/base/DecodersAndSanitizers/Protocols")"

print_section "Vault decoders (composed)" \
  "$(search_files "$SEARCH" "${ROOT}/src/base/DecodersAndSanitizers" | grep -v Protocols || true)"

print_section "MerkleTreeHelper matches" \
  "$(search_content "$SEARCH" "${ROOT}/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol")"

print_section "Integration tests" \
  "$(search_files "$SEARCH" "${ROOT}/test/integrations")"

if command -v rg >/dev/null; then
  ADDR_MATCHES="$(rg -l -i "$SEARCH" "${ROOT}/test/resources" -g '*Addresses.sol' 2>/dev/null || true)"
else
  ADDR_MATCHES="$(grep -ril "$SEARCH" "${ROOT}/test/resources" --include='*Addresses.sol' 2>/dev/null || true)"
fi
print_section "ChainValues / Addresses" "$ADDR_MATCHES"

print_section "Merkle root scripts" \
  "$(search_files "$SEARCH" "${ROOT}/script/MerkleRootCreation")"
