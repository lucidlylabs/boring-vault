---
name: boring-vault-tx-integrate
description: >-
  Integrate a new protocol into any deployed boring-vault (BTCCarry, ETHUSDCarry,
  LoopOptimiser, SyUsd, LiquidEth, etc.) from an Etherscan/block explorer tx URL.
  Always drafts an integration plan (tx flow, functions, signatures) for the user
  before coding. Then ingests calldata, resolves vault wiring, drafts decoder/sanitizer,
  Merkle leaves, and fork integration tests. Use when given a tx link + vault name.
  Works in Cursor, Codex CLI (.agents/skills), and Claude Code (.claude/skills).
---

# Boring Vault Tx Integration

Turn an explorer transaction into boring-vault artifacts for **any deployed vault**: decoder, Merkle leaves, integration test.

**Agent output is always a draft PR.** Never broadcast transactions or run on-chain scripts.

## Agent install (Cursor, Codex, Claude)

Canonical skill lives in this repo. Symlink for all agents:

```bash
./script/install-agent-skills.sh
# optional: ~/.claude/skills and ~/.cursor/skills
./script/install-agent-skills.sh --global
```

| Agent | Project path |
|-------|----------------|
| Cursor | `.cursor/skills/boring-vault-tx-integrate/` |
| Codex CLI | `.agents/skills/boring-vault-tx-integrate/` |
| Claude Code | `.claude/skills/boring-vault-tx-integrate/` |

See [INSTALL.md](INSTALL.md) for details.

**Prompt template:** `Use boring-vault-tx-integrate skill. Vault: btccarry. Tx: <explorer_url>`

## Hard rules (non-negotiable)

1. **Never commit.** Do not run `git commit`, `git push`, or open PRs unless the human explicitly asks. End with a clear summary of file changes only.
2. **Iterate until green.** Run targeted `forge test --match-contract <Integration>` after every change; fix decoder, leaves, and tests until **all** tests pass and the **exact reference tx calldata** is wired through merkle verification (protocol execution may still `expectRevert` for signatures/expiry — document why).
3. **Never run a full repo compile.** Do not run bare `forge build`, `forge build --force`, or unscoped `forge test`. **Only** targeted test commands below.
4. **Never execute on-chain transactions.** No `forge script ... --broadcast`, `cast send`, or `setManageRoot` broadcast.
5. **Never deploy decoders** from the agent. Human deploys after review.
6. **Mandatory security audit (Gate G4 + G5 + G9)** before marking work complete.
7. **Merkle root changes** → tell the human which script to edit; do not broadcast merkle scripts.
8. **Plan before code.** After ingest, draft an **integration plan** (tx flow, functions, signatures, addresses, test strategy) and **present it to the user in chat** before writing decoder/leaves/tests. Do not skip straight to implementation.

## Quick start

```bash
# 1. Ensure .env has RPC for the tx chain
cp sample.env .env   # fill MAINNET_RPC_URL etc.

# 2. Resolve target vault (human names: btccarry, ethusdcarry, syusd, loopoptimiser, …)
./script/vault-lookup.sh <vault_name>

# 3. Ingest reference tx (read-only RPC)
./script/tx-ingest.sh https://etherscan.io/tx/0xYOUR_TX_HASH

# 4. Check existing coverage
./script/coverage-check.sh <protocol_name>

# 5. POST integration plan to user (Phase 2) — then implement

# 6. Validate with TARGETED tests only (repo is large — avoid full forge build)
forge test --match-contract <NewIntegration> -vvv --no-match-contract MerkleTreeChecker
```

### Fast validation (large repo)

This repo compiles slowly (~600+ project `.sol` files, heavy `lib/` deps). **Agents must never run `forge build`.**

```bash
# REQUIRED: .env must have MAINNET_RPC_URL (or chain RPC) for fork tests
cp sample.env .env   # human fills RPC keys

# Preferred: compile + run only the new integration test
forge test --match-contract SyUsdJamSettlementIntegration -vvv --no-match-contract MerkleTreeChecker

# If MerkleTreeHelper changed, also run checker (slower — still targeted)
forge test --match-contract MerkleTreeChecker -vvv
```

Even a targeted `--match-contract` run may compile ~200 files (~60–90s) due to decoder inheritance — that is expected; a full build compiles thousands and can take many minutes.

## Phase 0 — Resolve vault (required)

The human must name the **target vault** (not inferred from tx alone). Examples: `btccarry`, `ethusdcarry`, `btc carry strategy`, `loopoptimiser`, `syusd`, `liquideth`.

```bash
./script/vault-lookup.sh btccarry
```

From results, record:

| Artifact | Where to find |
|----------|----------------|
| Deployment config | `deployments/configurations/{Chain}/{Vault}.json` |
| On-chain addresses | `deployments/addresses/` (manager, vault, decoder) |
| Composed vault decoder | `src/base/DecodersAndSanitizers/{Vault}DecoderAndSanitizer.sol` |
| Merkle root script(s) | `script/MerkleRootCreation/{Chain}/Create*MerkleRoot*.s.sol` |
| Leaf JSON output | `leafs/{Chain}/*.json` (path in script) |
| Deploy decoder entry | `script/DeployDecoderAndSanitizer.s.sol` |

**Gate G0:** Confirm vault + chain match the reference tx. A mainnet Jam tx for SyUsd does not auto-apply to Base BTCCarry — repeat wiring per vault/chain if needed.

Known deployed vault shortcuts — full table in [reference.md](reference.md#vault-resolution):

| Vault keyword | Decoder (typical) | Mainnet merkle script |
|---------------|-------------------|------------------------|
| `btccarry` / `btcusdcarry` | `BTCCarryDecoderAndSanitizer` | `CreateBTCUSDCarryClusterMerkleRoot.s.sol` |
| `ethusdcarry` | `BTCCarryDecoderAndSanitizer` (shared cluster) | `CreateETHUSDCarryClusterMerkleRoot.sol` |
| `btccarrystrategy` | `BTCCarryDecoderAndSanitizer` | `CreateBtcCarryStrategyMerkleRoot.s.sol` |
| `loopoptimiser` | `LoopOptimiserClusterDecoderAndSanitizer` | `CreateLoopOptimiserClusterMerkleRoot.s.sol` |
| `syusd` | `SyUsdDecoderAndSanitizer` | `CreateSyUsdMerkleRoot.s.sol` (+ chain variants) |
| `liquideth` | `EtherFiLiquidEthDecoderAndSanitizer` | grep `LiquidEth` under `MerkleRootCreation/` |

Always run `vault-lookup.sh` — names and chains drift; the script is source of truth.

## Phase 1 — Ingest

Run `./script/tx-ingest.sh <url>` and read `script/tx-ingest/output/<hash>.json`.

**Classify the tx (Gate G1):**

| Type | Meaning |
|------|---------|
| `MANAGE_BATCH` | Direct `manageVaultWithMerkleVerification` or vault `manage()` — decode inner arrays |
| `REFERENCE_PROTOCOL_TX` | EOA/protocol tx — reconstruct as manage batch for boring vault |
| `FLASH_LOAN_BUNDLE` | Outer flash loan + nested manage in `userData` |
| `UNKNOWN` | Stop; ask human |

For `REFERENCE_PROTOCOL_TX`, remap recipients/`onBehalfOf` → `address(boringVault)` in reconstructed calldata.

## Phase 2 — Integration plan (mandatory — tell the user)

**Stop after ingest.** Draft a plan and **post it to the user in chat** before Phase 4 (decoder) or any file edits. If the user’s message already says “implement” / “go ahead”, you may proceed after showing the plan inline.

Use this structure (fill every section; mark unknowns explicitly):

### Integration plan template

```markdown
## Integration plan — {Protocol} → {Vault} ({Chain})

**Reference tx:** {explorer link}
**Block:** {blockNumber}
**Classification:** {MANAGE_BATCH | REFERENCE_PROTOCOL_TX | …}

### Tx flow
1. {who calls whom — e.g. EOA → JamSettlement.settle}
2. {value / ETH sent}
3. {nested calls — swaps, approvals, bridges}
4. {how this maps to manageVaultWithMerkleVerification batch}

### Functions & selectors
| Step | Target contract | Function | Selector | Role |
|------|-----------------|----------|----------|------|
| … | … | … | … | … |

### Signatures & replay constraints
- {EIP-712 / permit / order nonce / expiry?}
- {Can exact calldata execute on fork? expectRevert why?}
- {What must be remapped to boringVault for production leaves?}

### Addresses to whitelist (decoder output order)
1. {address} — {role}
2. …

### Sanitization policy
- {array length limits, hooks, bytes fields, aggregator paths}

### Repo impact (draft)
- Decoder: {**extend** | net-new | **no change**} `{Protocol}DecoderAndSanitizer` — explain why
- Vault composer: {no change | inherit/override if needed}
- Leaves: {reuse `_add{Protocol}Leafs` with new arrays | extend helper | net-new helper}
- Merkle script: {append `_add*Leafs(...)` call | no change}
- Test: {add case to `ExistingIntegration.t.sol` | new file}
- ChainValues keys: {only new addresses}

### Risks / open questions
- {…}

**Awaiting your OK to implement** (or proceed if you already asked to implement).
```

**Gate G2 (blocker):** User has seen the plan. Do not write decoder/leaves/tests until plan is posted (unless user explicitly requested immediate implementation in the same turn).

See [reference.md — Example plan](reference.md#example-integration-plan-jam-settlement) for a filled-in example.

## Phase 3 — Coverage check

Run `./script/coverage-check.sh <protocol>` and grep:

- `src/base/DecodersAndSanitizers/Protocols/*DecoderAndSanitizer.sol`
- `MerkleTreeHelper._add{Protocol}Leafs`
- `test/integrations/*Integration.t.sol`
- Target vault decoder from Phase 0 (`{Vault}DecoderAndSanitizer.sol`)
- Addresses in `test/resources/ChainValues.sol` (via `getAddress`)

### Extend existing code — do not rewrite

When the protocol is **already integrated**, treat new txs as **new markets / pairs / routes** on top of existing helpers. **Never replace** a working decoder, leaf helper, or integration test file unless the human asks for a refactor or the tx exposes a **new function selector / calldata shape**.

| What exists | New market (e.g. new sell/buy pair) | New selector / calldata shape |
|-------------|--------------------------------------|------------------------------|
| **Decoder** | **No change** — same `settle`/`swap` extracts addresses from calldata | **Extend** decoder — add function or tighten sanitization; keep existing functions |
| **`_add*Leafs`** | **Reuse helper** — pass new `sellTokens`/`buyTokens`/pools; dedup maps skip duplicates | **Extend helper** only if new leaf fields needed; don't delete old leaf logic |
| **Integration test** | **Add test case** to existing `*Integration.t.sol` (new calldata constant + fork block) | Add tests for new selector; keep old tests passing |
| **Vault decoder** | **No change** if protocol decoder unchanged | Add inheritance/`override` only if new decoder mixin |
| **Merkle script** | **Add one call** in `_addLeafs()` with new market arrays | Same — append call; don't remove prior `_add*Leafs` calls |
| **ChainValues** | Add keys only for **new contract addresses** (router, pool) | Same |

**Example (Jam already integrated, new WETH → USDT market):**
- Decoder: unchanged (`JamSettlementDecoderAndSanitizer.sol`)
- Leaves: another `_addJamSettlementLeafs(leafs, wethSell, usdtBuy, executor, router)` in merkle script
- Test: new `test_wethUsdtReferenceTx()` in `SyUsdJamSettlementIntegration.t.sol` with that tx's calldata
- Plan must say **"extend — no decoder rewrite"**

**When to touch the decoder anyway:** new hooks path, multi-interaction shape, different struct, or sanitization gap found in audit — then **extend** with new reverts/fields, not a full file rewrite.

| Situation | Action |
|-----------|--------|
| Decoder + leaves + test exist; **same selectors**, new pair/market | Extend only: new `_add*Leafs` args + new test case + merkle script line |
| Decoder exists, no leaves for this vault | Add `_add*Leafs` call + integration test; **do not rewrite** decoder |
| Decoder exists but **new selector** in tx | Extend decoder with new function; add leaves + tests |
| Nothing exists | Phases 4–8 (net-new protocol) |

## Phase 4 — Decoder / sanitizer

Create or extend `src/base/DecodersAndSanitizers/Protocols/{Protocol}DecoderAndSanitizer.sol`:

- One `external pure/view` function per whitelisted selector
- Return `abi.encodePacked(...)` of **address-type** args only
- Add `DecoderCustomTypes` for struct params; revert on invalid shapes (see Karak)
- Sanitize `bytes`/callbacks/permits/aggregator paths — decode-only is insufficient
- Add `// Example TX https://...` with source tx URL
- Compose into vault decoder with explicit `override(A, B)` for collisions

**Gate G4 (blocker):** Human reviews extracted addresses and sanitization.

## Phase 5 — Merkle leaves

Add `_add{Protocol}Leafs(ManageLeaf[] memory leafs, ...)` to `test/resources/MerkleTreeHelper/MerkleTreeHelper.sol`:

- Use `leafIndex++` pattern (`leafIndex` starts at `type(uint256).max`)
- Reuse sub-helpers (`_addERC4626Leafs`, approve dedup maps)
- Set `canSendValue: true` when tx sends native ETH
- Include prerequisite leaves (approve, permit2, wrap) from trace
- Tree needs ≥2 leaves (pad with dummy if needed)
- For drone: `_createDroneLeafs`, `DroneLib.TARGET_FLAG`

Leaf hash: `keccak256(decoder ‖ target ‖ valueNonZero ‖ selector ‖ packedAddresses)`

**Gate G5 (blocker):** Human reviews leaf minimality — no over-broad token/router matrices.

## Phase 5.5 — Validate leaves (wiring)

```solidity
_verifyDecoderImplementsLeafsFunctionSelectors(leafs);
// For each non-padding leaf: staticcall decoder(reference targetData)
//   → packed output must equal leaf.argumentAddresses byte-for-byte
```

Run wiring checklist in [reference.md](reference.md#wiring-checklist-mandatory).

## Phase 6 — Integration test

Extend `BaseTestIntegration` (preferred). Tests run on a **fork only** — no live txs.

Required tests:
1. Decoder extracts expected addresses from reference calldata
2. `_verifyDecoderImplementsLeafsFunctionSelectors` passes
3. Merkle proof verifies (may `expectRevert` on protocol if signature/order invalid)
4. At least one negative `test_RevertWhen_*` sanitization case

## Phase 7 — Validate (read-only, iterate until green)

```bash
source .env   # MAINNET_RPC_URL required for fork tests
forge test --match-contract <NewIntegration> -vvv --no-match-contract MerkleTreeChecker
# only if MerkleTreeHelper shared helpers changed:
forge test --match-contract MerkleTreeChecker -vvv
```

**Do not stop after one failure.** Loop: read trace → fix decoder/leaves/test → re-run until all tests pass.

### Done criteria (integration)

- [ ] Decoder `staticcall` on **exact** reference tx calldata → packed bytes match leaf `argumentAddresses`
- [ ] `_verifyDecoderImplementsLeafsFunctionSelectors` passes
- [ ] `manageVaultWithMerkleVerification` accepts **exact** reference `targetData` (merkle path green)
- [ ] If protocol needs signatures/nonces: `expectRevert` on execute is OK — note in summary; do not fake signatures
- [ ] Negative sanitization test reverts
- [ ] Security audit checklist (G9) documented
- [ ] **Final message lists every file changed** — no git commit from agent

## Phase 8 — Production handoff (human only)

**Agent stops here.** Provide the human a checklist tailored to the **vault from Phase 0**:

1. **Vault decoder** — `{Vault}DecoderAndSanitizer.sol` inherits new protocol decoder (+ `override` for collisions).
2. **Merkle script** — edit the `Create*MerkleRoot*.s.sol` from `vault-lookup.sh`; add `_add{Protocol}Leafs(...)` inside `_addLeafs()`.
3. **ChainValues** — protocol keys for the tx chain.
4. **DeployDecoderAndSanitizer.s.sol** — only if a new composed decoder must be deployed (human broadcasts).
5. **Dry-run** — human runs `forge script <merkle_script> --rpc-url $RPC -vvvv` **without** `--broadcast`.
6. **Review leaf JSON** — diff the `leafs/{Chain}/*.json` path emitted by that script before `setManageRoot`.

```bash
# Example — human only, after vault-lookup.sh identified the script
source .env
forge script script/MerkleRootCreation/Mainnet/CreateBTCUSDCarryClusterMerkleRoot.s.sol \
  --rpc-url $MAINNET_RPC_URL -vvvv
# forge script ... --broadcast   # human only after G8 security sign-off
```

**Never run:** `forge script ... --broadcast`, `setManageRoot` on live manager, or deploy decoder from agent session.

Vault-specific script lists: [reference.md — Vault resolution](reference.md#vault-resolution).

## Security audit checklist (mandatory G9)

Before presenting work as complete, verify and document each item:

### Decoder security
- [ ] Every sensitive `address` in calldata is extracted — none omitted
- [ ] `bytes` / callback / permit fields sanitized or reverted (not left open)
- [ ] Struct/array lengths constrained where policy requires fixed shape
- [ ] Aggregator/router paths cannot redirect to arbitrary tokens via opaque `bytes`
- [ ] No `pure` decoder reading chain state incorrectly; `view` only when needed

### Leaf security
- [ ] Each `argumentAddresses[i]` is minimal and justified (no `type(uint256).max` approve leaves unless intentional)
- [ ] No combinatorial explosion of swap leaves unless product requirement
- [ ] `canSendValue` correct for native ETH sends
- [ ] Prerequisite approvals (permit2, ERC20) included for full tx path

### Wiring correctness
- [ ] Protocol decoder composed into correct **target vault** decoder (from Phase 0)
- [ ] `DecoderCustomTypes` structs added if needed
- [ ] `ChainValues` keys added with checksummed addresses
- [ ] `_add*Leafs` argument order matches decoder `abi.encodePacked` order
- [ ] `_getProofsUsingTree` uses same `rawDataDecoderAndSanitizer` as leaf `decoderAndSanitizer` field
- [ ] `_verifyDecoderImplementsLeafsFunctionSelectors(leafs)` passes
- [ ] Reference tx calldata: decoder staticcall output == leaf `argumentAddresses` packed
- [ ] Integration test negative case reverts on invalid input

### Production handoff
- [ ] Correct vault merkle script + leaf JSON path identified for human (from `vault-lookup.sh`)
- [ ] No agent-executed broadcasts or deployments
- [ ] Human notified to review leaf JSON diff and run security sign-off (G4, G5, G8)

## Human review gates

| Gate | When | Blocker? |
|------|------|----------|
| G0 | After vault lookup | Vault + chain match tx |
| G1 | After ingest | Tx classification |
| G2 | After plan drafted | **Yes** — user must see plan before coding |
| G3 | After coverage | Reuse vs net-new scope |
| G4 | After decoder | **Yes** — security |
| G5 | After leaves | **Yes** — leaf minimality |
| G6–G7 | After test | Fidelity + assertions |
| G8 | Before prod root | **Yes** — JSON diff (human runs script) |
| G9 | Before PR ready | **Yes** — security audit checklist complete |

## Reference flows

See [reference.md](reference.md) for Gearbox (simple), Hyperlane (hard), and Jam Settlement (aggregator) patterns.

## Key files

| File | Purpose |
|------|---------|
| `script/vault-lookup.sh` | Vault name → config, decoder, merkle scripts |
| `script/install-agent-skills.sh` | Symlink skill for Cursor / Codex / Claude |
| `script/tx-ingest.sh` | Tx URL → JSON (read-only) |
| `script/coverage-check.sh` | Grep decoders/leaves/tests |
| `test/integrations/BaseTestIntegration.t.sol` | Fork test base |
| `test/resources/MerkleTreeHelper/MerkleTreeHelper.sol` | Leaf helpers |
| `src/base/Roles/ManagerWithMerkleVerification.sol` | Verification logic |
| `test/MerkleTreeChecker.t.sol` | Decoder coverage regression |

## Limitations

- Amounts are not whitelisted — only addresses
- Internal trace calls are context; only top-level manage calls need proofs
- Signed orders (Jam, 1inch backend sig, etc.) cannot be fully replayed without new signatures
- `cast run` is slow; use `tx-ingest.sh` without `--trace` first
