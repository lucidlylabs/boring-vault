#!/usr/bin/env bash
# Install boring-vault-tx-integrate skill for Cursor, Codex, and Claude Code.
#
# Usage:
#   ./script/install-agent-skills.sh           # project-local symlinks
#   ./script/install-agent-skills.sh --global  # also link into ~/.claude/skills and ~/.cursor/skills

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_NAME="boring-vault-tx-integrate"
SRC="${ROOT}/.cursor/skills/${SKILL_NAME}"
GLOBAL=false

for arg in "$@"; do
  case "$arg" in
    --global) GLOBAL=true ;;
    -h|--help)
      echo "Usage: ./script/install-agent-skills.sh [--global]"
      exit 0
      ;;
  esac
done

[[ -f "${SRC}/SKILL.md" ]] || { echo "error: missing ${SRC}/SKILL.md" >&2; exit 1; }

link_skill() {
  local dest_dir="$1"
  mkdir -p "$dest_dir"
  local dest="${dest_dir}/${SKILL_NAME}"
  if [[ "$(cd "$SRC" && pwd -P)" == "$(cd "$dest" 2>/dev/null && pwd -P)" ]]; then
    echo "skip ${dest} (canonical source)"
    return
  fi
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    echo "skip ${dest} (exists and is not a symlink)"
    return
  fi
  ln -sfn "$SRC" "$dest"
  echo "linked ${dest} -> ${SRC}"
}

echo "Installing ${SKILL_NAME} skill..."
echo ""

# Cursor (project — primary source of truth in repo)
link_skill "${ROOT}/.cursor/skills"

# Codex CLI / open agent standard
link_skill "${ROOT}/.agents/skills"

# Claude Code (project)
link_skill "${ROOT}/.claude/skills"

if $GLOBAL; then
  link_skill "${HOME}/.cursor/skills"
  link_skill "${HOME}/.claude/skills"
  # Codex user-level if present
  [[ -d "${HOME}/.codex" ]] && link_skill "${HOME}/.codex/skills" || true
fi

chmod +x "${ROOT}/script/tx-ingest.sh" "${ROOT}/script/coverage-check.sh" "${ROOT}/script/vault-lookup.sh" 2>/dev/null || true

echo ""
echo "Done. Skill paths:"
echo "  Cursor (project):  .cursor/skills/${SKILL_NAME}/SKILL.md"
echo "  Codex (project):   .agents/skills/${SKILL_NAME}/SKILL.md"
echo "  Claude (project):  .claude/skills/${SKILL_NAME}/SKILL.md"
echo ""
echo "Invoke in prompts: use boring-vault-tx-integrate skill for vault <name> and tx <url>"
