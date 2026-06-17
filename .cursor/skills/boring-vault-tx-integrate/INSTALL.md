# Agent skill install locations

Canonical source (edit here):

- [`.cursor/skills/boring-vault-tx-integrate/`](.cursor/skills/boring-vault-tx-integrate/)

Install symlinks for Codex + Claude:

```bash
./script/install-agent-skills.sh
# optional global (~/.claude/skills, ~/.cursor/skills):
./script/install-agent-skills.sh --global
```

| Agent | Project path | Global path |
|-------|--------------|-------------|
| **Cursor** | `.cursor/skills/boring-vault-tx-integrate/` | `~/.cursor/skills/boring-vault-tx-integrate/` |
| **Codex CLI** | `.agents/skills/boring-vault-tx-integrate/` | `~/.codex/skills/boring-vault-tx-integrate/` (if used) |
| **Claude Code** | `.claude/skills/boring-vault-tx-integrate/` | `~/.claude/skills/boring-vault-tx-integrate/` |

Prompt prefix (all agents):

> Use the `boring-vault-tx-integrate` skill. Vault: **btccarry**. Tx: https://etherscan.io/tx/0x...

Helper scripts:

```bash
./script/vault-lookup.sh btccarry
./script/tx-ingest.sh <explorer_tx_url>
./script/coverage-check.sh <protocol>
```
