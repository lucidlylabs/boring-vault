#!/usr/bin/env bash
# Ingest an EVM explorer transaction URL and emit structured JSON for boring-vault integration.
#
# Usage:
#   ./script/tx-ingest.sh <explorer_tx_url> [--trace]
#
# Requires: cast, jq, rg (optional). Sources .env from repo root for RPC URLs.
# Output: script/tx-ingest/output/<txHash>.json

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/script/tx-ingest/output"
TRACE=false

MANAGE_VAULT_SELECTOR="0x244b0f6a"
MANAGE_SINGLE_SELECTOR="0xf6e715d0"
MANAGE_BATCH_SELECTOR="0x224d8703"
FLASH_LOAN_SELECTOR="0x5c38449e"
RECEIVE_FLASH_LOAN_SELECTOR="0xf04f2707"

usage() {
  cat <<'EOF'
Usage: ./script/tx-ingest.sh <explorer_tx_url> [--trace]

Examples:
  ./script/tx-ingest.sh https://etherscan.io/tx/0xabc...
  ./script/tx-ingest.sh https://arbiscan.io/tx/0xabc... --trace

Environment (from repo .env):
  MAINNET_RPC_URL, BASE_RPC_URL, ARBITRUM_RPC_URL, BNB_RPC_URL, ...
  ETHERSCAN_KEY (optional, for cast interface)
EOF
}

die() { echo "error: $*" >&2; exit 1; }

if [[ $# -lt 1 ]]; then usage; exit 1; fi

URL="$1"
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace) TRACE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ -f "${ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${ROOT}/.env"
  set +a
fi

command -v cast >/dev/null || die "cast not found (install Foundry)"
command -v jq >/dev/null || die "jq not found"

parse_explorer_url() {
  local url="$1"

  if [[ "$url" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
    CHAIN="mainnet"
    RPC_ENV="MAINNET_RPC_URL"
    TX_HASH="$url"
    EXPLORER_URL="https://etherscan.io/tx/${TX_HASH}"
    return
  fi

  local host hash
  host="$(echo "$url" | sed -E 's#https?://([^/]+)/.*#\1#')"
  hash="$(echo "$url" | sed -E 's#.*(0x[a-fA-F0-9]{64}).*#\1#')"
  [[ "$hash" =~ ^0x[a-fA-F0-9]{64}$ ]] || die "could not parse tx hash from URL: $url"
  TX_HASH="$hash"
  EXPLORER_URL="$url"

  case "$host" in
    etherscan.io) CHAIN="mainnet"; RPC_ENV="MAINNET_RPC_URL" ;;
    arbiscan.io) CHAIN="arbitrum"; RPC_ENV="ARBITRUM_RPC_URL" ;;
    basescan.org) CHAIN="base"; RPC_ENV="BASE_RPC_URL" ;;
    bscscan.com) CHAIN="bsc"; RPC_ENV="BNB_RPC_URL" ;;
    sonicscan.org) CHAIN="sonicMainnet"; RPC_ENV="SONIC_MAINNET_RPC_URL" ;;
    berascan.com) CHAIN="berachain"; RPC_ENV="BERA_CHAIN_RPC_URL" ;;
    swellscan.io) CHAIN="swell"; RPC_ENV="SWELL_CHAIN_RPC_URL" ;;
    optimism.etherscan.io) CHAIN="optimism"; RPC_ENV="OPTIMISM_RPC_URL" ;;
    polygonscan.com) CHAIN="polygon"; RPC_ENV="POLYGON_RPC_URL" ;;
    lineascan.build) CHAIN="linea"; RPC_ENV="LINEA_RPC_URL" ;;
    scrollscan.com) CHAIN="scroll"; RPC_ENV="SCROLL_RPC_URL" ;;
    blastscan.io) CHAIN="blast"; RPC_ENV="BLAST_RPC_URL" ;;
    *) CHAIN="unknown"; RPC_ENV="" ;;
  esac
}

get_rpc() {
  if [[ -z "$RPC_ENV" ]]; then
    die "unknown chain for explorer host; extend chain mapping in script/tx-ingest.sh"
  fi
  RPC_URL="${!RPC_ENV:-}"
  [[ -n "$RPC_URL" && "$RPC_URL" != "..." ]] || die "${RPC_ENV} not set in .env"
}

selector() {
  local input="$1"
  [[ ${#input} -ge 10 ]] || { echo "null"; return; }
  echo "${input:0:10}"
}

classify_tx() {
  CLASSIFICATION="REFERENCE_PROTOCOL_TX"
  RISKS='[]'

  add_risk() {
    RISKS="$(echo "$RISKS" | jq --arg r "$1" '. + [$r] | unique')"
  }

  case "$SELECTOR" in
    "$MANAGE_VAULT_SELECTOR"|"$MANAGE_SINGLE_SELECTOR"|"$MANAGE_BATCH_SELECTOR")
      CLASSIFICATION="MANAGE_BATCH"
      ;;
    "$FLASH_LOAN_SELECTOR"|"$RECEIVE_FLASH_LOAN_SELECTOR")
      CLASSIFICATION="FLASH_LOAN_BUNDLE"
      add_risk "FLASH_LOAN"
      ;;
  esac

  if [[ "$VALUE" != "0x0" && "$VALUE" != "0" && -n "$VALUE" ]]; then
    add_risk "NONZERO_VALUE"
  fi

  if [[ ${#INPUT} -gt 200 ]]; then
    add_risk "LARGE_CALLDATA"
  fi
}

decode_top_level() {
  FOURBYTE_DECODE=""
  if [[ ${#INPUT} -ge 10 ]]; then
    FOURBYTE_DECODE="$(cast 4byte-decode "$INPUT" 2>/dev/null || true)"
  fi
}

decode_manage_vault_batch() {
  MANAGE_BATCH_JSON='null'
  [[ "$CLASSIFICATION" == "MANAGE_BATCH" && "$SELECTOR" == "$MANAGE_VAULT_SELECTOR" ]] || return 0

  local decoded
  decoded="$(cast calldata-decode \
    "manageVaultWithMerkleVerification(bytes32[][],address[],address[],bytes[],uint256[])" \
    "$INPUT" 2>/dev/null || true)"
  [[ -n "$decoded" ]] || return 0

  MANAGE_BATCH_JSON="$(jq -n --arg raw "$decoded" \
    '{rawDecode: $raw, note: "Parse targets/targetData/values arrays for per-call analysis"}')"
}

coverage_hints() {
  EXISTING_DECODERS='[]'
  EXISTING_LEAF_HELPERS='[]'
  EXISTING_INTEGRATION_TESTS='[]'
  EXAMPLE_TX_DECODERS='[]'

  local target_lower files
  target_lower="$(echo "$TO" | tr '[:upper:]' '[:lower:]')"

  if command -v rg >/dev/null; then
    files="$(rg -l "${target_lower}" "${ROOT}/src/base/DecodersAndSanitizers" 2>/dev/null || true)"
  else
    files="$(grep -ril "${target_lower}" "${ROOT}/src/base/DecodersAndSanitizers" 2>/dev/null || true)"
  fi
  if [[ -n "$files" ]]; then
    EXISTING_DECODERS="$(echo "$files" | xargs -I{} basename {} .sol | jq -R -s 'split("\n") | map(select(length>0))')"
  fi

  if command -v rg >/dev/null; then
    files="$(rg -l "${target_lower}" "${ROOT}/test/integrations" 2>/dev/null || true)"
  else
    files="$(grep -ril "${target_lower}" "${ROOT}/test/integrations" 2>/dev/null || true)"
  fi
  if [[ -n "$files" ]]; then
    EXISTING_INTEGRATION_TESTS="$(echo "$files" | xargs -I{} basename {} | jq -R -s 'split("\n") | map(select(length>0))')"
  fi

  if command -v rg >/dev/null; then
    files="$(rg -l "${TX_HASH}" "${ROOT}/src/base/DecodersAndSanitizers" 2>/dev/null || true)"
    EXISTING_LEAF_HELPERS="$(rg -o "_add[A-Za-z0-9]+Leafs" "${ROOT}/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol" 2>/dev/null | sort -u | jq -R -s 'split("\n") | map(select(length>0))' || echo '[]')"
  else
    files="$(grep -rl "${TX_HASH}" "${ROOT}/src/base/DecodersAndSanitizers" 2>/dev/null || true)"
    EXISTING_LEAF_HELPERS="$(grep -oE '_add[A-Za-z0-9]+Leafs' "${ROOT}/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol" 2>/dev/null | sort -u | jq -R -s 'split("\n") | map(select(length>0))' || echo '[]')"
  fi
  if [[ -n "$files" ]]; then
    EXAMPLE_TX_DECODERS="$(echo "$files" | xargs -I{} basename {} .sol | jq -R -s 'split("\n") | map(select(length>0))')"
  fi
}

maybe_trace() {
  TRACE_OUTPUT='null'
  $TRACE || return 0
  echo "Running cast run trace (may be slow)..." >&2
  local trace_file="${OUT_DIR}/${TX_HASH}.trace.txt"
  cast run "$TX_HASH" --rpc-url "$RPC_URL" -vvvv >"$trace_file" 2>&1 || true
  TRACE_OUTPUT="$(jq -n --arg path "$trace_file" '{traceFile: $path}')"
}

parse_explorer_url "$URL"
get_rpc

echo "Fetching tx ${TX_HASH} on ${CHAIN}..." >&2

TX_JSON="$(cast tx "$TX_HASH" --rpc-url "$RPC_URL" --json)"
RECEIPT_JSON="$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json)"

TO="$(echo "$TX_JSON" | jq -r '.to // empty')"
FROM="$(echo "$TX_JSON" | jq -r '.from')"
INPUT="$(echo "$TX_JSON" | jq -r '.input')"
VALUE="$(echo "$TX_JSON" | jq -r '.value')"
BLOCK_HEX="$(echo "$TX_JSON" | jq -r '.blockNumber')"
BLOCK_NUMBER="$(cast --to-dec "$BLOCK_HEX")"
SELECTOR="$(selector "$INPUT")"
STATUS="$(echo "$RECEIPT_JSON" | jq -r '.status')"

classify_tx
decode_top_level
decode_manage_vault_batch
coverage_hints
maybe_trace

mkdir -p "$OUT_DIR"
OUTPUT_FILE="${OUT_DIR}/${TX_HASH}.json"

jq -n \
  --arg txHash "$TX_HASH" \
  --arg chain "$CHAIN" \
  --argjson blockNumber "$BLOCK_NUMBER" \
  --arg explorerUrl "$EXPLORER_URL" \
  --arg rpcEnv "$RPC_ENV" \
  --arg classification "$CLASSIFICATION" \
  --arg from "$FROM" \
  --arg to "$TO" \
  --arg value "$VALUE" \
  --arg selector "$SELECTOR" \
  --arg input "$INPUT" \
  --arg fourbyteDecode "$FOURBYTE_DECODE" \
  --arg status "$STATUS" \
  --argjson risks "$RISKS" \
  --argjson manageBatch "${MANAGE_BATCH_JSON:-null}" \
  --argjson existingDecoders "${EXISTING_DECODERS:-[]}" \
  --argjson existingLeafHelpers "${EXISTING_LEAF_HELPERS:-[]}" \
  --argjson existingIntegrationTests "${EXISTING_INTEGRATION_TESTS:-[]}" \
  --argjson exampleTxDecoders "${EXAMPLE_TX_DECODERS:-[]}" \
  --argjson trace "${TRACE_OUTPUT:-null}" \
  '{
    meta: {
      txHash: $txHash,
      chain: $chain,
      blockNumber: $blockNumber,
      explorerUrl: $explorerUrl,
      rpcEnv: $rpcEnv,
      status: $status
    },
    classification: $classification,
    topLevel: {
      from: $from,
      to: $to,
      value: $value,
      selector: $selector,
      input: $input,
      fourbyteDecode: (if $fourbyteDecode == "" then null else $fourbyteDecode end)
    },
    manageBatch: $manageBatch,
    coverageHints: {
      existingDecoders: $existingDecoders,
      existingLeafHelpers: $existingLeafHelpers,
      existingIntegrationTests: $existingIntegrationTests,
      exampleTxDecoders: $exampleTxDecoders
    },
    risks: $risks,
    trace: $trace,
    nextSteps: [
      "Confirm classification (human gate G1)",
      "Run ./script/coverage-check.sh <protocol>",
      "If REFERENCE_PROTOCOL_TX: reconstruct manage batch from trace",
      "Fork at blockNumber via BaseTestIntegration._setupChain",
      "Complete security audit checklist (gate G8) in .cursor/skills/boring-vault-tx-integrate/SKILL.md",
      "For SyUsd: human updates script/MerkleRootCreation/Mainnet/CreateSyUsdMerkleRoot.s.sol — never agent --broadcast",
      "Validate: forge test --match-contract <Integration> -vvv (avoid full forge build)"
    ]
  }' >"$OUTPUT_FILE"

echo "$OUTPUT_FILE"
jq . "$OUTPUT_FILE"
