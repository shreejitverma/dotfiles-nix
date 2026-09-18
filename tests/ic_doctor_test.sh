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
#   - check every ~/github/agents/grok/agents/*.md link, whatever the names
#   - never check ~/.grok/config.toml (Grok owns and rewrites that file)
#   - warn once, without failing, when ~/github/agents is not cloned
#   - name the missing source when the agents repo lacks GROK.md or grok/agents
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
assert_line_count() {
  local n
  n=$(grep -cE "$2" <<<"$1" 2>/dev/null || true)
  if [ "$n" = "$3" ]; then ok "$4"; else fail "$4 (got $n lines matching '$2', want $3)"; fi
}

new_home() {
  local home="$SANDBOX/home-$1"
  mkdir -p "$home"
  printf '%s\n' "$home"
}

plant_grok_bin() {
  local dest="$1"
  local version="${2:-grok 1.0.34 (deadbeef) [stable]}"
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' '#!/bin/bash' "echo '$version'" >"$dest"
  chmod +x "$dest"
}

plant_grok_skills() {
  local home="$1"
  local s
  mkdir -p "$home/.grok/skills"
  for s in $SKILLS; do
    mkdir -p "$home/.agents/skills/$s"
    printf '%s\n' "# $s" >"$home/.agents/skills/$s/SKILL.md"
    ln -sfn "../../.agents/skills/$s" "$home/.grok/skills/$s"
  done
}

plant_wiring() {
  local home="$1"
  local repo="$home/github/agents"
  mkdir -p "$repo/claude" "$repo/grok/agents" "$home/.claude" "$home/.grok/agents"
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
  printf '%s\n' 'auto_update = true' >"$home/.grok/config.toml"
  ln -sf "$repo/grok/agents/implementer.md" "$home/.grok/agents/implementer.md"
  ln -sf "$repo/grok/agents/reviewer.md" "$home/.grok/agents/reviewer.md"
  ln -sf "$repo/OPINIONS.md" "$home/OPINIONS.md"
  ln -sf "$repo/VOICE.md" "$home/VOICE.md"
  ln -sf "$repo/claude/settings.json" "$home/.claude/settings.json"
  plant_grok_skills "$home"
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
assert_grep "$section" 'ok    grok: 2 agent definitions linked' \
  "accepts grok agent definitions linked from the agents repo"
assert_not_grep "$section" 'config\.toml' \
  "does not check the Grok-owned regular file ~/.grok/config.toml"
assert_grep "$section" 'ok    personal layer versioned in ~/github/agents' \
  "personal layer check passes without any ~/.grok entry"
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
assert_line_count "$section" 'FAIL .*\.grok/AGENTS\.md' 1 \
  "a mislinked ~/.grok/AGENTS.md yields exactly one FAIL line"

# --- any version string is accepted at the official path ---
home=$(new_home other-channel)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok" "grok 2.0.0 (cafef00d) [canary]"
section=$(run_section7 "$home")
assert_grep "$section" 'ok    grok grok 2\.0\.0 \(cafef00d\) \[canary\]' \
  "accepts an unrecognised channel label from the binary at ~/.local/bin/grok"
assert_not_grep "$section" 'FAIL  grok' \
  "does not FAIL on the version string format"

# --- agent definitions follow the repo, not a fixed name list ---
home=$(new_home renamed-agent)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
mv "$home/github/agents/grok/agents/reviewer.md" "$home/github/agents/grok/agents/auditor.md"
rm "$home/.grok/agents/reviewer.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok: agent definitions not linked: auditor\.md \(run: ic-link\)' \
  "fails naming an agent definition that is in the repo but not linked"
ln -sf "$home/github/agents/grok/agents/auditor.md" "$home/.grok/agents/auditor.md"
section=$(run_section7 "$home")
assert_grep "$section" 'ok    grok: 2 agent definitions linked' \
  "accepts a renamed agent definition once it is linked"
assert_not_grep "$section" 'reviewer' \
  "does not expect an agent name the repo no longer has"

# --- Grok installed, private agents repo not cloned ---
home=$(new_home no-agents-repo)
mkdir -p "$home/.grok"
printf '%s\n' 'auto_update = true' >"$home/.grok/config.toml"
plant_grok_skills "$home"
plant_grok_bin "$home/.local/bin/grok"
section=$(run_section7 "$home")
assert_line_count "$section" 'warn  grok: private agents repo not cloned' 1 \
  "warns once when Grok is installed but ~/github/agents is not cloned"
assert_grep "$section" 'ok    grok: all skills linked' \
  "still checks the skill mirrors without the agents repo"
assert_not_grep "$section" 'FAIL  (grok|GROK)' \
  "does not FAIL grok checks when ~/github/agents is not cloned"

# --- agents repo present but missing the Grok sources ---
home=$(new_home no-grok-sources)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
rm -rf "$home/github/agents/GROK.md" "$home/github/agents/grok/agents"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok: ~/github/agents/GROK\.md missing' \
  "names the missing GROK.md source file"
assert_grep "$section" 'FAIL  grok: no agent definitions at ~/github/agents/grok/agents/\*\.md' \
  "names the missing grok/agents source"
assert_not_grep "$section" 'FAIL  (grok|GROK)[^(]*\(run: ic-link\)' \
  "does not offer a bare 'run: ic-link' when the source is absent"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "ic_doctor_test: all checks passed"
  exit 0
fi
echo "ic_doctor_test: $FAILS failure(s)"
exit 1
