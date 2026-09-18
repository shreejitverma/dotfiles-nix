#!/bin/bash
#
# ic_link_test.sh: sandbox regression test for files/bin/ic-link's Grok wiring.
#
# Runs the real ic-link against a fake $HOME. It must:
#   - never create ~/.grok (the Grok installer owns that directory)
#   - never touch ~/.grok/hooks (firstmate owns the turn-end hook)
#   - never point ~/.grok/AGENTS.md at Claude's ~/AGENTS.md
#   - link Grok's own AGENTS.md, config.toml, skills, and agent definitions
#     from ~/github/agents when that repo is present
#
# Nothing touches the real home directory or the network.
# Honours DEBUG_KEEP_SANDBOX=1 to leave the scratch directory on disk.
#
# Run: bash tests/ic_link_test.sh
set -uo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && cd .. && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/ic-link-test.XXXXXX")"

cleanup() {
  if [ "${DEBUG_KEEP_SANDBOX:-0}" = "1" ]; then
    echo "DEBUG_KEEP_SANDBOX=1: sandbox left at $SANDBOX"
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

FAILS=0
ok()   { printf 'ok: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; FAILS=$((FAILS + 1)); }

assert_eq() {
  if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (got '$1', want '$2')"; fi
}
assert_file() {
  if [ -e "$1" ]; then ok "$2"; else fail "$2 ($1 missing)"; fi
}
assert_no_path() {
  if [ -e "$1" ]; then fail "$2 ($1 exists)"; else ok "$2"; fi
}

new_home() {
  local home="$SANDBOX/home-$1"
  mkdir -p "$home"
  printf '%s\n' "$home"
}

seed_agents_repo() {
  local home="$1"
  local repo="$home/github/agents"
  mkdir -p "$repo/claude" "$repo/grok/agents"
  printf '%s\n' '# Claude operating manual' >"$repo/CLAUDE.md"
  printf '%s\n' '# Grok operating manual' '## Default development system' >"$repo/GROK.md"
  printf '%s\n' 'opinions' >"$repo/OPINIONS.md"
  printf '%s\n' 'voice' >"$repo/VOICE.md"
  printf '%s\n' '{}' >"$repo/claude/settings.json"
  printf '%s\n' 'default = "grok-4.6"' >"$repo/grok/config.toml"
  printf '%s\n' '# implementer' >"$repo/grok/agents/implementer.md"
  printf '%s\n' '# reviewer' >"$repo/grok/agents/reviewer.md"
}

run_link() {
  local home="$1"
  if ! HOME="$home" "$REPO_ROOT/files/bin/ic-link"; then
    fail "ic-link exited non-zero for $home"
    return 1
  fi
}

# --- never create ~/.grok ---
home=$(new_home no-grok)
seed_agents_repo "$home"
run_link "$home" >/dev/null
assert_no_path "$home/.grok" "ic-link does not create ~/.grok when the installer has not"

# --- full Grok personal layer ---
home=$(new_home grok-full)
seed_agents_repo "$home"
mkdir -p "$home/.grok/hooks"
printf '%s\n' '{"keep":true}' >"$home/.grok/hooks/fm-keep.json"
printf '%s\n' 'stale-claude-pointer' >"$home/.grok/AGENTS.md"
printf '%s\n' 'stale-config' >"$home/.grok/config.toml"
run_link "$home" >/dev/null

assert_eq "$(readlink "$home/.grok/AGENTS.md")" "$home/github/agents/GROK.md" \
  "~/.grok/AGENTS.md points at GROK.md, not Claude's file"
assert_eq "$(readlink "$home/.grok/config.toml")" "$home/github/agents/grok/config.toml" \
  "~/.grok/config.toml points at the versioned grok config"
assert_eq "$(readlink "$home/.grok/agents/implementer.md")" "$home/github/agents/grok/agents/implementer.md" \
  "implementer agent definition is linked"
assert_eq "$(readlink "$home/.grok/agents/reviewer.md")" "$home/github/agents/grok/agents/reviewer.md" \
  "reviewer agent definition is linked"
if [ -L "$home/.grok/skills/ship" ]; then
  ok "grok skill mirror for ship is a symlink"
else
  fail "grok skill mirror for ship is not a symlink"
fi
assert_eq "$(readlink "$home/.grok/skills/ship")" "../../.agents/skills/ship" \
  "grok skill mirrors use the same relative target as claude/codex"
assert_file "$home/.grok/hooks/fm-keep.json" "existing firstmate hook file is left in place"
assert_eq "$(find "$home/.grok/hooks" -mindepth 1 | wc -l | tr -d ' ')" "1" \
  "ic-link does not add files under ~/.grok/hooks"
assert_eq "$(readlink "$home/AGENTS.md")" ".claude/CLAUDE.md" \
  "cross-tool ~/AGENTS.md still points at Claude"

# --- missing GROK.md must not fall back to Claude ---
home=$(new_home grok-no-manual)
mkdir -p "$home/github/agents/claude" "$home/.grok"
printf '%s\n' '# Claude' >"$home/github/agents/CLAUDE.md"
printf '%s\n' '{}' >"$home/github/agents/claude/settings.json"
printf '%s\n' 'opinions' >"$home/github/agents/OPINIONS.md"
printf '%s\n' 'voice' >"$home/github/agents/VOICE.md"
printf '%s\n' 'preexisting' >"$home/.grok/AGENTS.md"
out=$(run_link "$home" 2>&1) || true
if grep -q "GROK.md missing" <<<"$out"; then
  ok "warns when GROK.md is missing"
else
  fail "should warn when GROK.md is missing"
fi
if [ "$(readlink "$home/.grok/AGENTS.md" 2>/dev/null)" = "$home/AGENTS.md" ] \
   || [ "$(readlink "$home/.grok/AGENTS.md" 2>/dev/null)" = "$home/github/agents/CLAUDE.md" ]; then
  fail "must not point ~/.grok/AGENTS.md at Claude's file when GROK.md is missing"
else
  ok "does not fall back to Claude's AGENTS.md when GROK.md is missing"
fi
if grep -q "preexisting" "$home/.grok/AGENTS.md"; then
  ok "leaves a preexisting ~/.grok/AGENTS.md in place when GROK.md is missing"
else
  fail "preexisting ~/.grok/AGENTS.md was replaced even though GROK.md is missing"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "ic_link_test: all checks passed"
  exit 0
fi
echo "ic_link_test: $FAILS failure(s)"
exit 1
