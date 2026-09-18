#!/bin/bash
#
# ic_doctor_test.sh: sandbox regression test for files/bin/ic-doctor's Grok checks.
#
# Runs the real ic-doctor against a fake $HOME. It must:
#   - skip Grok checks when ~/.grok is absent
#   - accept a single official binary at ~/.local/bin/grok plus GROK.md wiring
#   - fail when grok on PATH is not ~/.local/bin/grok
#   - fail when a second grok binary is on PATH
#   - fail when ~/.grok/AGENTS.md is not a symlink to ~/github/agents/GROK.md
#
# Other ic-doctor sections (checkout path, forks, host binaries) still run and
# may FAIL; this suite only asserts the Grok lines in section 7.
# Nothing touches the real home directory. Honours DEBUG_KEEP_SANDBOX=1.
#
# Run: bash tests/ic_doctor_test.sh
set -uo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && cd .. && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/ic-doctor-test.XXXXXX")"
SKILLS="axi chrome-devtools-axi gh-axi gnhf lavish no-mistakes quota-axi ship stow tasks-axi"

# shellcheck disable=SC2329  # invoked by the EXIT trap
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

assert_grep() {
  if grep -qE "$2" <<<"$1" 2>/dev/null; then ok "$3"; else fail "$3 (no match for '$2')"; fi
}
assert_not_grep() {
  if grep -qE "$2" <<<"$1" 2>/dev/null; then fail "$3 (unexpected match for '$2')"; else ok "$3"; fi
}

new_home() {
  local home="$SANDBOX/home-$1"
  mkdir -p "$home"
  printf '%s\n' "$home"
}

plant_grok_bin() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<'EOF'
#!/bin/bash
echo "grok 1.0.34 (deadbeef) [stable]"
EOF
  chmod +x "$dest"
}

plant_wiring() {
  local home="$1"
  local repo="$home/github/agents"
  local s
  mkdir -p "$repo/claude" "$repo/grok/agents" "$home/.claude" "$home/.grok/agents" "$home/.grok/skills"
  printf '%s\n' '# Claude operating manual' '## Default development system' >"$repo/CLAUDE.md"
  printf '%s\n' '# Grok operating manual' '## Default development system' >"$repo/GROK.md"
  printf '%s\n' 'opinions' >"$repo/OPINIONS.md"
  printf '%s\n' 'voice' >"$repo/VOICE.md"
  printf '%s\n' '{}' >"$repo/claude/settings.json"
  printf '%s\n' 'default = "grok-4.6"' >"$repo/grok/config.toml"
  printf '%s\n' '# implementer' >"$repo/grok/agents/implementer.md"
  printf '%s\n' '# reviewer' >"$repo/grok/agents/reviewer.md"
  ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
  ln -sf "$repo/CLAUDE.md" "$home/.claude/CLAUDE.md"
  ln -sf "$repo/GROK.md" "$home/.grok/AGENTS.md"
  ln -sf "$repo/grok/config.toml" "$home/.grok/config.toml"
  ln -sf "$repo/grok/agents/implementer.md" "$home/.grok/agents/implementer.md"
  ln -sf "$repo/grok/agents/reviewer.md" "$home/.grok/agents/reviewer.md"
  ln -sf "$repo/OPINIONS.md" "$home/OPINIONS.md"
  ln -sf "$repo/VOICE.md" "$home/VOICE.md"
  ln -sf "$repo/claude/settings.json" "$home/.claude/settings.json"
  for s in $SKILLS; do
    mkdir -p "$home/.agents/skills/$s"
    printf '%s\n' "# $s" >"$home/.agents/skills/$s/SKILL.md"
    ln -sfn "../../.agents/skills/$s" "$home/.grok/skills/$s"
  done
}

run_section7() {
  local home="$1"
  local log
  log="$SANDBOX/$(basename "$home").log"
  env -u NVM_DIR HOME="$home" "$REPO_ROOT/files/bin/ic-doctor" >"$log" 2>&1 || true
  awk '/\[7\/7\]/,0' "$log"
}

# --- skip when Grok is not installed ---
home=$(new_home no-grok)
section=$(run_section7 "$home")
assert_grep "$section" 'warn  grok not set up \(~/.grok absent\); skipping' \
  "skips Grok checks when ~/.grok is absent"
assert_not_grep "$section" 'FAIL  grok' \
  "does not FAIL grok checks when ~/.grok is absent"

# --- healthy official binary and personal layer ---
home=$(new_home healthy)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
section=$(run_section7 "$home")
assert_grep "$section" 'ok    grok grok 1\.0\.34 \(deadbeef\) \[stable\]' \
  "accepts the official grok binary at ~/.local/bin/grok"
assert_grep "$section" 'ok    grok: ~/.grok/AGENTS.md -> ~/github/agents/GROK.md' \
  "accepts ~/.grok/AGENTS.md linked to GROK.md"
assert_grep "$section" 'ok    GROK.md declares the default development system' \
  "accepts GROK.md with the default development system section"
assert_grep "$section" 'ok    grok: all skills linked' \
  "accepts grok skill mirrors"
assert_grep "$section" 'ok    grok: config.toml versioned in ~/github/agents' \
  "accepts ~/.grok/config.toml linked from the agents repo"
assert_grep "$section" 'ok    grok: implementer and reviewer agent definitions linked' \
  "accepts grok agent definitions linked from the agents repo"
assert_not_grep "$section" 'FAIL  grok' \
  "does not FAIL grok checks when wiring and the official binary are healthy"
assert_not_grep "$section" 'FAIL  GROK' \
  "does not FAIL GROK.md when it declares the default development system"

# --- grok on PATH is not the official installer path ---
home=$(new_home wrong-path)
plant_wiring "$home"
plant_grok_bin "$home/go/bin/grok"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok on PATH is .*/go/bin/grok, want ~/.local/bin/grok' \
  "fails when grok on PATH is not ~/.local/bin/grok"

# --- second grok binary on PATH ---
home=$(new_home dup)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
plant_grok_bin "$home/go/bin/grok"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok: 2 copies on PATH:' \
  "fails when a second grok binary is on PATH"
assert_grep "$section" 'keep ~/.local/bin/grok; npm uninstall -g @xai-official/grok' \
  "names the official binary and the npm uninstall to drop the extra copy"

# --- AGENTS.md must not point at Claude's file ---
home=$(new_home claude-pointer)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
ln -sfn "$home/AGENTS.md" "$home/.grok/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok: ~/.grok/AGENTS.md is not a symlink to ~/github/agents/GROK.md' \
  "fails when ~/.grok/AGENTS.md is not linked to GROK.md"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "ic_doctor_test: all checks passed"
  exit 0
fi
echo "ic_doctor_test: $FAILS failure(s)"
exit 1
