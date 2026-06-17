# Boring Vault Tx Integration — Reference

## Agent install (Cursor, Codex, Claude)

```bash
./script/install-agent-skills.sh
```

| Agent | Reads skill from |
|-------|------------------|
| Cursor | `.cursor/skills/boring-vault-tx-integrate/SKILL.md` |
| Codex CLI | `.agents/skills/boring-vault-tx-integrate/SKILL.md` (symlink) |
| Claude Code | `.claude/skills/boring-vault-tx-integrate/SKILL.md` (symlink) |

## Vault resolution

Always start with:

```bash
./script/vault-lookup.sh <vault_keyword>
```

### Known deployed vaults (shortcuts)

Verify with `vault-lookup.sh` — chains and script names change over time.

| Vault keyword | Config | Decoder | Merkle script (examples) | Leaf JSON (examples) |
|---------------|--------|---------|--------------------------|----------------------|
| `btccarry` / `btcusdcarry` | `deployments/configurations/Mainnet/BTCCarry.json` | `BTCCarryDecoderAndSanitizer` | `CreateBTCUSDCarryClusterMerkleRoot.s.sol` | `leafs/Mainnet/BTCUSDCarryClusterStrategistLeafs.json` |
| `ethusdcarry` | `deployments/configurations/Mainnet/ETHUSDCarryCluster.json` | `BTCCarryDecoderAndSanitizer` (shared) | `CreateETHUSDCarryClusterMerkleRoot.sol` | grep script for `filePath` |
| `btccarrystrategy` | `BtcCarry` in deployments | `BTCCarryDecoderAndSanitizer` | `CreateBtcCarryStrategyMerkleRoot.s.sol` (Mainnet), `BtcCarryStrategyMerkleRoot.s.sol` (Arbitrum) | `leafs/Mainnet/BtcCarryStrategyLeafs.json` |
| `btccarry` (Base) | `deployments/configurations/Base/BTCCarry.json` | `BTCCarryDecoderAndSanitizer` | `CreateBTCCarryMerkleRoot.s.sol` | `leafs/Base/BTCCarryStrategyLeafs.json` |
| `loopoptimiser` | LoopOptimiser cluster config | `LoopOptimiserClusterDecoderAndSanitizer` | `CreateLoopOptimiserClusterMerkleRoot.s.sol` | `leafs/Mainnet/LoopOptimiserClusterStrategistLeafs.json` |
| `syusd` | SyUsd configs (multi-chain) | `SyUsdDecoderAndSanitizer` | `CreateSyUsdMerkleRoot.s.sol` + chain variants | `leafs/Mainnet/SyUsdMainnetStrategist02Leafs.json` |
| `liquideth` | EtherFi liquid eth configs | `EtherFiLiquidEthDecoderAndSanitizer` | grep `LiquidEth` under `MerkleRootCreation/` | grep script `filePath` |

### Wiring per vault

1. Compose protocol into **`{Vault}DecoderAndSanitizer.sol`** (not always SyUsd).
2. Integration test name: `{Vault}{Protocol}Integration.t.sol` (e.g. `BTCCarryJamSettlementIntegration.t.sol`).
3. Merkle script: use `DECODER_AND_SANITIZER` / `rawDataDecoderAndSanitizer` from that script's `setUp()` — must match deployed decoder for that vault.
4. If multiple strategists/roots exist (SyUsd safe, morpho agent, etc.), human picks the script matching their operational root.

## Extending existing protocols (new markets)

**Default: extend, never rewrite.** Leaf helpers use dedup mappings (e.g. `ownerToJamSellTokenToBuyTokenToInTree`) so calling `_addJamSettlementLeafs` again with a new sell/buy pair **adds only the missing leaves** — existing pairs are skipped.

### Decision tree

```
Protocol decoder exists for this selector?
├─ YES → keep decoder; add markets via _add*Leafs + test case + merkle script line
└─ NO  → add decoder function (extend file, don't replace)

_add*Leafs helper exists?
├─ YES → call with new token/pool arrays
└─ NO  → add helper following existing patterns (Odos, 1inch, Jam)

Integration test file exists?
├─ YES → add test_* function with new REFERENCE_*_CALLDATA
└─ NO  → create {Vault}{Protocol}Integration.t.sol
```

### What “new market” usually means (no decoder change)

| Protocol type | “New market” | Typical change |
|---------------|--------------|----------------|
| Jam / 1inch / Odos | New sell→buy token pair | `_addJamSettlementLeafs(leafs, [newSell], [newBuy], executor, router)` |
| Morpho / Aave | New market id / reserve | `_addMorpho*Leafs` with new market address |
| Uniswap V3 | New pool fee tier | New leaf with pool NFT manager + token pair |
| Bridge | New destination chain | New leaf with endpoint/router from ChainValues |

### What requires decoder changes

- New function selector in the reference tx
- New struct layout or variable-length policy (e.g. allowing 2 interactions when previously 1)
- New sensitive address in calldata not yet extracted
- Sanitization bug found in audit

### Merkle script pattern (append only)

```solidity
// inside _addLeafs — keep existing calls, add new market:
address[] memory sell = new address[](1);
sell[0] = getAddress(sourceChain, "WETH");
address[] memory buy = new address[](1);
buy[0] = getAddress(sourceChain, "USDT");
_addJamSettlementLeafs(leafs, sell, buy, executor, getAddress(sourceChain, "jamInteractionRouter"));
```

Human regenerates leaf JSON; agent does not broadcast.

## Example integration plan (Jam Settlement)

Use this as a filled-in reference when drafting Phase 2 for the user:

```markdown
## Integration plan — Jam Settlement → SyUsd (mainnet)

**Reference tx:** https://etherscan.io/tx/0x9094a719fcbbe1882e0bf852b052983fa692af7532027256e344367e1c3fc5b5
**Block:** 25325442
**Classification:** REFERENCE_PROTOCOL_TX

### Tx flow
1. EOA `0x9076…` calls `JamSettlement.settle` with 0.0001 ETH
2. `settle` executes one interaction → Uniswap V4 router (`0xAC4c…`) swap ETH → USDC
3. For boring vault: same call shape via `manageVaultWithMerkleVerification` targeting `jamSettlement`

### Functions & selectors
| Step | Target | Function | Selector | Role |
|------|--------|----------|----------|------|
| 1 | `0xbeb0…` JamSettlement | `settle(order,bytes,interactions[],bytes,address)` | `0x2143d82c` | Primary manage target |
| 2 | `0xAC4c…` | router swap calldata in interaction | `0x5f3bd1c8` | Nested — context only |

### Signatures & replay constraints
- Jam order is signed off-chain; exact reference calldata **cannot fully execute** on fork (expired sig/nonce)
- Merkle + decoder tests use **exact** reference calldata; `expectRevert` on `settle` is expected
- Production leaves remap `taker`/`receiver` → `boringVault`; executor pinned via leaf args

### Addresses to whitelist (decoder `abi.encodePacked` order)
1. taker  2. receiver  3. executor  4. sellToken  5. buyToken  6. balanceRecipient  7. interaction.to

### Sanitization policy
- Exactly 1 sell token, 1 buy token, 1 interaction; revert on hooks / extra interactions

### Repo impact
- `JamSettlementDecoderAndSanitizer.sol`, inherit in `SyUsdDecoderAndSanitizer`
- `_addJamSettlementLeafs` in MerkleTreeHelper
- `SyUsdJamSettlementIntegration.t.sol` @ block 25325442
- ChainValues: `jamSettlement`, `jamInteractionRouter`

**Awaiting your OK to implement.**
```

## Agent constraints

- **Plan first, tell the user** — after ingest, post integration plan (tx flow, functions, signatures, addresses) in chat before coding.
- **Never commit** — summarize file changes at the end; human commits.
- **Iterate until green** — re-run targeted tests after each fix until all pass and exact reference calldata verifies through merkle.
- **Read-only on-chain:** `cast tx`, `cast call`, fork tests, `tx-ingest.sh` only.
- **Never:** `cast send`, `forge script --broadcast`, `setManageRoot` broadcast, deploy with live keys.
- **Merkle production:** draft code → human edits script → human runs `forge script` → human reviews JSON → human broadcasts.

## Leaf hash formula

```solidity
keccak256(abi.encodePacked(
    decoderAndSanitizer,  // 20 bytes
    target,               // 20 bytes
    valueNonZero,         // 1 byte bool
    selector,             // 4 bytes
    packedArgumentAddresses  // N × 20 bytes from decoder
))
```

Decoder output must **exactly match** `ManageLeaf.argumentAddresses` packed order.

## Wiring checklist (mandatory)

Run after Phase 4 and before marking integration complete:

| # | Check | How |
|---|-------|-----|
| 1 | Decoder in vault composer | Target `{Vault}DecoderAndSanitizer` inherits `{Protocol}DecoderAndSanitizer` |
| 2 | No selector collision | `forge build` or targeted test compiles; overrides resolve ambiguities |
| 3 | ChainValues keys | `getAddress(sourceChain, "protocolKey")` resolves in fork test |
| 4 | Leaf helper exists | `_add{Protocol}Leafs` in `MerkleTreeHelper.sol` |
| 5 | Selector coverage | `_verifyDecoderImplementsLeafsFunctionSelectors(leafs)` |
| 6 | Calldata parity | `staticcall(decoder, refCalldata)` packed bytes == `leaf.argumentAddresses` |
| 7 | Proof path | `_getProofsUsingTree` + `manageVaultWithMerkleVerification` (fork only) |
| 8 | Merkle script stub | Human-facing note: which `Create*MerkleRoot*.s.sol` to edit (from `vault-lookup.sh`) |
| 9 | Negative test | Decoder reverts on invalid shapes (extra interactions, hooks, etc.) |
| 10 | Security sign-off | Human completes G4, G5, G8 checklists in SKILL.md |

## Proof generation pattern

1. Build **full** leaf set → `_generateMerkleTree(leafs)`
2. `manager.setManageRoot(strategist, tree[tree.length - 1][0])` — **fork test only**
3. Pick **subset** `manageLeafs[]` matching the tx call sequence
4. `_getProofsUsingTree(manageLeafs, manageTree)`
5. `manageVaultWithMerkleVerification(proofs, decoders, targets, targetData, values)`

## Production wiring (any vault)

### Vault decoder

Edit `src/base/DecodersAndSanitizers/{Vault}DecoderAndSanitizer.sol` — add inheritance + collision overrides.

Constructor args vary by vault — copy from existing deploy script in `script/DeployDecoderAndSanitizer.s.sol` (e.g. `DeployBTCCarryDecoderAndSanitizer`, `DeploySyUsdDecoderAndSanitizer`).

### Merkle root scripts (human runs these)

Add `_add{Protocol}Leafs(...)` inside `_addLeafs()` in the script returned by `./script/vault-lookup.sh <vault>`.

**SyUsd** (multi-chain) scripts when vault is `syusd`:

```
script/MerkleRootCreation/Mainnet/CreateSyUsdMerkleRoot.s.sol      → leafs/Mainnet/SyUsdMainnetStrategist02Leafs.json
script/MerkleRootCreation/Mainnet/CreateSyUsdMerkleRootSafe.s.sol
script/MerkleRootCreation/Mainnet/CreateSyUsdMorphoAgentMerkleRoot.s.sol
script/MerkleRootCreation/Base/CreateSyUsdMultiChainMerkleRoot.s.sol
script/MerkleRootCreation/Arbitrum/CreateSyUsdArbitrumLeafs.sol
script/MerkleRootCreation/Katana/CreateSyUsdKatanaMerkleRoot.s.sol
script/MerkleRootCreation/Plasma/CreateSyUsdLeafs.s.sol
script/CreateSyUsdEthereumLeafs.sol
```

**BTCCarry / ETHUSDCarry** (mainnet cluster):

```
script/MerkleRootCreation/Mainnet/CreateBTCUSDCarryClusterMerkleRoot.s.sol
script/MerkleRootCreation/Mainnet/CreateETHUSDCarryClusterMerkleRoot.sol
```

**LoopOptimiser:**

```
script/MerkleRootCreation/Mainnet/CreateLoopOptimiserClusterMerkleRoot.s.sol
```

Example addition (human applies after review):

```solidity
// inside _addLeafs(ManageLeaf[] memory leafs)
address[] memory jamSell = new address[](1);
jamSell[0] = getAddress(sourceChain, "ETH");
address[] memory jamBuy = new address[](1);
jamBuy[0] = getAddress(sourceChain, "USDC");
_addJamSettlementLeafs(
    leafs,
    jamSell,
    jamBuy,
    getAddress(sourceChain, "dev4Address"),
    getAddress(sourceChain, "jamInteractionRouter")
);
```

Script pattern (human executes — replace script with vault-specific path):

```bash
source .env
./script/vault-lookup.sh btccarry   # pick merkle script from output
forge script script/MerkleRootCreation/Mainnet/CreateBTCUSDCarryClusterMerkleRoot.s.sol \
  --rpc-url $MAINNET_RPC_URL -vvvv
# forge script ... --broadcast   # human only after JSON + security review
```

### Deploy decoder (human only)

Update [`script/DeployDecoderAndSanitizer.s.sol`](../../script/DeployDecoderAndSanitizer.s.sol) if a new composed decoder must be deployed. Human broadcasts deploy separately, then updates `rawDataDecoderAndSanitizer` address in merkle script `setUp()`.

## Reference flow A — Gearbox (simple)

**Files:** `GearboxDecoderAndSanitizer.sol`, `_addGearboxLeafs`, `GearboxIntegration.t.sol`

- Decoder returns **empty bytes** for `deposit(uint256)`, `withdraw(uint256)`, `claim()`
- Leaf helper calls `_addERC4626Leafs` first, then adds approve + staking leaves

## Reference flow B — Hyperlane (hard)

**Files:** `HyperlaneDecoderAndSanitizer.sol`, `HyperlaneBridgeIntegration.t.sol`

- Non-literal address packing: `bytes32` recipient split into two `address` values
- Cross-chain addresses from `getAddress(sourceChain, ...)`

## Reference flow C — Jam Settlement (aggregator, signed orders)

**Files:** `JamSettlementDecoderAndSanitizer.sol`, `_addJamSettlementLeafs`, `SyUsdJamSettlementIntegration.t.sol` (example vault: SyUsd — replicate pattern for BTCCarry etc.)

**Reference TX:** https://etherscan.io/tx/0x9094a719fcbbe1882e0bf852b052983fa692af7532027256e344367e1c3fc5b5

- Target: `jamSettlement` (`0xbeb0b0623f66bE8cE162EbDfA2ec543A522F4ea6`)
- Native ETH → USDC via `settle(...)` with `canSendValue: true`
- Decoder packs: `taker, receiver, executor, sellToken, buyToken, balanceRecipient, interaction.to`
- Sanitization: single sell/buy token, single interaction, no hooks
- **Cannot replay full settle on fork** without valid Jam signature — test decoder + merkle path; `expectRevert` on execute

ChainValues keys:
- `jamSettlement`
- `jamInteractionRouter`
- `dev4Address` (executor in reference tx)

## Decoder sanitization checklist

- [ ] All sensitive `address` args extracted and packed in correct order
- [ ] `bytes` / `bytes[]` fields constrained or reverted
- [ ] Array/struct length fixed where policy requires single pool/vault
- [ ] Permit/permit2 paths blocked or pinned
- [ ] Aggregator swap paths cannot redirect to arbitrary tokens
- [ ] `view` only when decoder reads on-chain state

## Integration test checklist

- [ ] Fork at tx `blockNumber`
- [ ] `deal()` tokens / ETH into `boringVault` as needed
- [ ] `_overrideDecoder(address)` with composed vault decoder
- [ ] Merkle tree ≥ 2 leaves (padding leaf if needed)
- [ ] `_verifyDecoderImplementsLeafsFunctionSelectors`
- [ ] Decoder staticcall on reference calldata
- [ ] Negative sanitization test
- [ ] **No live transaction submission**

## Fast test commands

```bash
# Resolve vault first
./script/vault-lookup.sh btccarry

# Single integration test (preferred)
forge test --match-contract SyUsdJamSettlementIntegration -vvv

# Merkle helper regression (only when MerkleTreeHelper changed)
forge test --match-contract MerkleTreeChecker -vvv

# Read-only tx ingest
./script/tx-ingest.sh https://etherscan.io/tx/0x...
./script/coverage-check.sh jam
```

Avoid `forge build` entirely — agents use `forge test --match-contract` only. Full repo compile is for humans when they explicitly need it.

## Address registry

Add to [`test/resources/ChainValues.sol`](../../test/resources/ChainValues.sol) with **EIP-55 checksummed** addresses:

```solidity
values[mainnet]["jamSettlement"] = 0xbeb0b0623f66bE8cE162EbDfA2ec543A522F4ea6.toBytes32();
```

Use `getAddress(sourceChain, "key")` in leaf helpers and tests.
