#!/usr/bin/env bash
# Resolve a deployed vault name to config, merkle scripts, decoder, and leaf output paths.
#
# Usage:
#   ./script/vault-lookup.sh <vault_name_or_keyword>
#   ./script/vault-lookup.sh btccarry
#   ./script/vault-lookup.sh ethusdcarry
#   ./script/vault-lookup.sh loopoptimiser

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERM="${1:-}"

if [[ -z "$TERM" ]]; then
  cat <<'EOF'
Usage: ./script/vault-lookup.sh <vault_name_or_keyword>

Examples:
  ./script/vault-lookup.sh btccarry
  ./script/vault-lookup.sh ethusdcarry
  ./script/vault-lookup.sh syusd
  ./script/vault-lookup.sh loopoptimiser
  ./script/vault-lookup.sh liquideth
EOF
  exit 1
fi

SEARCH="$(echo "$TERM" | tr '[:upper:]' '[:lower:]')"

# Expand aliases so related artifacts are found (decoder names != config names)
EXTRA_TERMS=("$SEARCH")
case "$SEARCH" in
  ethusdcarry|ethcarry|ethusdcarrycluster)
    EXTRA_TERMS+=("ethusdcarry" "btccarry" "btcusdcarry")
    ;;
  btccarry|btcusdcarry|btccarrycluster)
    EXTRA_TERMS+=("btccarry" "btcusdcarry" "btccarrydecoder")
    ;;
  btccarrystrategy|btccarrystrategy)
    EXTRA_TERMS+=("btccarry" "btccarrystrategy")
    ;;
  loopoptimiser|loopoptimizer)
    EXTRA_TERMS+=("loopoptimiser" "loopoptimisercluster")
    ;;
  syusd|sy-usd)
    EXTRA_TERMS+=("syusd")
    ;;
esac

search_files() {
  local pattern="$1"
  local path="$2"
  if command -v rg >/dev/null; then
    rg -l -i "$pattern" "$path" 2>/dev/null || true
  else
    grep -ril "$pattern" "$path" 2>/dev/null || true
  fi
}

search_all_terms() {
  local path="$1"
  local -a results=()
  local t
  for t in "${EXTRA_TERMS[@]}"; do
    while IFS= read -r line; do
      [[ -n "$line" ]] && results+=("$line")
    done < <(search_files "$t" "$path")
  done
  printf '%s\n' "${results[@]}" | sort -u
}

echo "=== Vault lookup: ${TERM} ==="
echo ""

echo "--- Deployment configurations (deployments/configurations/) ---"
search_all_terms "${ROOT}/deployments/configurations" | sed 's/^/  /' || echo "  (none)"
echo ""

echo "--- Deployment addresses (deployments/addresses/) ---"
search_all_terms "${ROOT}/deployments/addresses" | sed 's/^/  /' || echo "  (none)"
echo ""

echo "--- Merkle root scripts (script/MerkleRootCreation/) ---"
search_all_terms "${ROOT}/script/MerkleRootCreation" | sed 's/^/  /' || echo "  (none)"
echo ""

echo "--- Ad-hoc leaf scripts (script/) ---"
search_all_terms "${ROOT}/script" | grep -i merkle | grep -iv MerkleRootCreation | sed 's/^/  /' || echo "  (none)"
echo ""

echo "--- Composed vault decoders (src/base/DecodersAndSanitizers/) ---"
search_all_terms "${ROOT}/src/base/DecodersAndSanitizers" \
  | grep -v Protocols | sed 's/^/  /' || echo "  (none)"
echo ""

echo "--- Deploy decoder entries (script/DeployDecoderAndSanitizer.s.sol) ---"
search_all_terms "${ROOT}/script/DeployDecoderAndSanitizer.s.sol" | sed 's/^/  /' || echo "  (none)"
echo ""

echo "--- Generated leaf JSON (leafs/) ---"
search_all_terms "${ROOT}/leafs" | sed 's/^/  /' || echo "  (none)"
echo ""

echo "--- Integration tests (test/integrations/) ---"
search_all_terms "${ROOT}/test/integrations" | sed 's/^/  /' || echo "  (none)"
echo ""

echo "Next: compose protocol decoder into vault decoder above, add _add*Leafs to MerkleTreeHelper,"
echo "add call in the matching Create*MerkleRoot script, run targeted forge test."
echo "See .cursor/skills/boring-vault-tx-integrate/SKILL.md (also in .agents/skills and .claude/skills)."
