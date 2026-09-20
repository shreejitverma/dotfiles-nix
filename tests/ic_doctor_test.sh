#!/bin/bash
#
# ic_doctor_test.sh: sandbox regression test for files/bin/ic-doctor's per-tool
# manual checks (the cross-tool ~/AGENTS.md chain, Grok, and Gemini).
#
# Runs the real ic-doctor against a fake $HOME. It must:
#   - accept ~/AGENTS.md linked to the tool-neutral agents/AGENTS.md, fail when
#     it resolves to Claude's manual instead, fail when it dangles, fail naming
#     bin/build-manuals when the repo is cloned but the neutral build is not
#     generated, and accept the Claude fallback only with no agents repo at all
#   - fail when any of the four manuals has lost the 'Default development
#     system' routing section, not only when Claude's has
#   - skip Grok checks when ~/.grok is absent
#   - accept a single official binary at ~/.local/bin/grok plus GROK.md wiring
#   - fail when grok on PATH is not ~/.local/bin/grok
#   - fail when a second grok binary is on PATH
#   - fail when ~/.grok/AGENTS.md is not a symlink to ~/github/agents/GROK.md,
#     naming the actual target, whether or not GROK.md or the agents repo exists
#   - check every ~/github/agents/grok/agents/*.md link, whatever the names
#   - fail on a dangling ~/.grok/agents link whose agents-repo source is gone
#   - never check ~/.grok/config.toml (Grok owns and rewrites that file)
#   - warn once, without failing, when ~/github/agents is not cloned
#   - name the missing source when the agents repo lacks GROK.md (FAIL) or
#     grok/agents (warn only: agent definitions are optional)
#   - skip Gemini checks when ~/.gemini is absent, and otherwise fail when
#     ~/.gemini/AGENTS.md is not linked to GEMINI.md, naming the actual target
#     whether or not GEMINI.md or the agents repo exists, when GEMINI.md is
#     missing from the repo, when ~/.gemini/GEMINI.md (Gemini's memory file) has
#     been made a symlink, or when a linked manual is not listed in
#     context.fileName, while never blaming context.fileName where no manual is
#     linked at all
#
# Other ic-doctor sections (checkout path, forks, host binaries) still run and
# may FAIL; this suite only asserts section 7.
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
  printf '%s\n' '# Tool-neutral manual' '## Default development system' >"$repo/AGENTS.md"
  printf '%s\n' '# Gemini operating manual' '## Default development system' >"$repo/GEMINI.md"
  printf '%s\n' '# Grok operating manual' '## Default development system' >"$repo/GROK.md"
  printf '%s\n' 'opinions' >"$repo/OPINIONS.md"
  printf '%s\n' 'voice' >"$repo/VOICE.md"
  printf '%s\n' '{}' >"$repo/claude/settings.json"
  printf '%s\n' 'default = "grok-4.6"' >"$repo/grok/config.toml"
  printf '%s\n' '# implementer' >"$repo/grok/agents/implementer.md"
  printf '%s\n' '# reviewer' >"$repo/grok/agents/reviewer.md"
  ln -sfn "$repo/AGENTS.md" "$home/AGENTS.md"
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

plant_gemini() {
  local home="$1"
  mkdir -p "$home/.gemini"
  printf '%s\n' '## Gemini Added Memories' >"$home/.gemini/GEMINI.md"
  printf '%s\n' '{"context": {"fileName": ["AGENTS.md", "GEMINI.md"]}}' >"$home/.gemini/settings.json"
  ln -sfn "$home/github/agents/GEMINI.md" "$home/.gemini/AGENTS.md"
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
assert_grep "$section" "FAIL  grok: ~/.grok/AGENTS.md points at $home/AGENTS\.md, not ~/github/agents/GROK\.md \(run: ic-link\)" \
  "fails naming Claude's manual as the target when ~/.grok/AGENTS.md points at it"
assert_line_count "$section" 'FAIL .*\.grok/AGENTS\.md' 1 \
  "a mislinked ~/.grok/AGENTS.md yields exactly one FAIL line"

# --- a missing GROK.md must not hide a link to Claude's manual ---
home=$(new_home claude-pointer-no-manual)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
rm "$home/github/agents/GROK.md"
ln -sfn "$home/AGENTS.md" "$home/.grok/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok: ~/github/agents/GROK\.md missing' \
  "reports the missing GROK.md source"
assert_grep "$section" "FAIL  grok: ~/.grok/AGENTS.md points at $home/AGENTS\.md, not ~/github/agents/GROK\.md \(add ~/github/agents/GROK\.md, then run: ic-link\)" \
  "still names Claude's manual as the target, as its own line, when GROK.md is missing"

# --- nor must an uncloned agents repo ---
home=$(new_home claude-pointer-no-repo)
mkdir -p "$home/.grok"
plant_grok_skills "$home"
plant_grok_bin "$home/.local/bin/grok"
ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
ln -sfn "$home/AGENTS.md" "$home/.grok/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" "FAIL  grok: ~/.grok/AGENTS.md points at $home/AGENTS\.md, not ~/github/agents/GROK\.md" \
  "names Claude's manual as the target even when ~/github/agents is not cloned"
assert_line_count "$section" 'warn  grok: private agents repo not cloned' 1 \
  "still warns once about the uncloned agents repo"

# --- a regular file is not Grok's versioned manual ---
home=$(new_home manual-regular-file)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
rm "$home/.grok/AGENTS.md"
printf '%s\n' 'loose manual' >"$home/.grok/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok: ~/.grok/AGENTS.md is missing or not a symlink to ~/github/agents/GROK\.md \(run: ic-link\)' \
  "fails when ~/.grok/AGENTS.md is a regular file"

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
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok: agent definitions not linked: auditor\.md \(run: ic-link\)' \
  "fails naming an agent definition that is in the repo but not linked"
ln -sf "$home/github/agents/grok/agents/auditor.md" "$home/.grok/agents/auditor.md"
section=$(run_section7 "$home")
assert_grep "$section" 'ok    grok: 2 agent definitions linked' \
  "accepts a renamed agent definition once it is linked"
assert_grep "$section" 'FAIL  grok: dangling agent links, source gone from ~/github/agents/grok/agents: reviewer\.md \(remove: cd ~/.grok/agents && rm reviewer\.md\)' \
  "fails naming the dangling link a rename leaves behind, with the command that removes it"
rm "$home/.grok/agents/reviewer.md"
ln -s "$home/elsewhere/mine.md" "$home/.grok/agents/mine.md"
section=$(run_section7 "$home")
assert_not_grep "$section" 'FAIL  (grok|GROK)' \
  "passes once the dangling link is removed, ignoring a dangling link that never pointed into the agents repo"
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

# --- agents repo as the README describes it: GROK.md, no grok/agents ---
home=$(new_home no-grok-agents)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
rm -rf "$home/github/agents/grok/agents"
rm "$home/.grok/agents/implementer.md" "$home/.grok/agents/reviewer.md"
section=$(run_section7 "$home")
assert_line_count "$section" 'warn  grok: no agent definitions at ~/github/agents/grok/agents/\*\.md' 1 \
  "warns once when the agents repo has no grok/agents"
assert_not_grep "$section" 'FAIL  (grok|GROK)' \
  "passes the Grok checks without any agent definitions"

# --- agents repo present but missing the Grok sources ---
home=$(new_home no-grok-sources)
plant_wiring "$home"
plant_grok_bin "$home/.local/bin/grok"
rm -rf "$home/github/agents/GROK.md" "$home/github/agents/grok/agents"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  grok: ~/github/agents/GROK\.md missing' \
  "names the missing GROK.md source file"
assert_line_count "$section" 'FAIL .*\.grok/AGENTS\.md' 0 \
  "does not blame a ~/.grok/AGENTS.md that already points at GROK.md for the missing source"
assert_line_count "$section" 'warn  grok: no agent definitions at ~/github/agents/grok/agents/\*\.md' 1 \
  "warns once, naming the missing grok/agents source"
assert_not_grep "$section" 'FAIL  grok: no agent definitions' \
  "does not FAIL on the absent optional grok/agents source"
assert_grep "$section" 'FAIL  grok: dangling agent links, source gone from ~/github/agents/grok/agents: implementer\.md reviewer\.md \(remove: cd ~/.grok/agents && rm implementer\.md reviewer\.md\)' \
  "names every link left dangling when the repo has no agent definitions at all"
assert_not_grep "$section" 'FAIL  (grok|GROK)[^(]*\(run: ic-link\)' \
  "does not offer a bare 'run: ic-link' when the source is absent"

# --- the cross-tool ~/AGENTS.md chain carries the tool-neutral manual ---
home=$(new_home neutral-manual)
plant_wiring "$home"
section=$(run_section7 "$home")
assert_grep "$section" 'ok    ~/AGENTS.md -> agents/AGENTS.md \(tool-neutral\)' \
  "accepts ~/AGENTS.md linked to the tool-neutral manual"
assert_not_grep "$section" 'FAIL  ~/AGENTS.md' \
  "does not FAIL the cross-tool chain when it carries the neutral manual"
assert_grep "$section" 'ok    agents/AGENTS.md declares the default development system' \
  "checks the routing section in the manual Codex resolves to, not only Claude's"

# --- the neutral manual Codex reads has lost the routing section ---
home=$(new_home neutral-manual-no-routing)
plant_wiring "$home"
printf '%s\n' '# Tool-neutral manual' >"$home/github/agents/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" "FAIL  agents/AGENTS.md missing the 'Default development system' section" \
  "fails when the neutral manual no longer declares the default development system"
assert_grep "$section" 'ok    CLAUDE.md declares the default development system' \
  "still reports Claude's own manual separately, since Claude reads it directly"

# --- ~/AGENTS.md pointing at Claude's manual while a neutral build exists ---
home=$(new_home neutral-manual-claude-pointer)
plant_wiring "$home"
ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" "FAIL  ~/AGENTS.md still resolves to Claude's manual, so Codex reads Claude-only rules \(run: ic-link\)" \
  "fails when ~/AGENTS.md resolves to Claude's manual though a neutral build exists"

# --- agents repo cloned, neutral manual never generated ---
home=$(new_home neutral-manual-not-generated)
plant_wiring "$home"
rm "$home/github/agents/AGENTS.md"
ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  ~/github/agents/AGENTS.md not generated.*\(run: ~/github/agents/bin/build-manuals, then ic-link\)' \
  "fails naming build-manuals when the repo is cloned but the neutral build is missing"
assert_not_grep "$section" 'ok    ~/AGENTS.md' \
  "does not report the Claude fallback as ok while the agents repo is cloned"

# --- no agents repo at all: the Claude fallback is the only target there is ---
home=$(new_home no-agents-repo-fallback)
mkdir -p "$home/.claude"
printf '%s\n' '# Claude operating manual' '## Default development system' >"$home/.claude/CLAUDE.md"
ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'ok    ~/AGENTS.md -> ~/.claude/CLAUDE.md \(no agents repo; neutral manual unavailable\)' \
  "accepts the Claude fallback when the agents repo is not cloned"

# --- the same fallback target, with nothing behind it ---
home=$(new_home agents-md-dangling)
ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  ~/AGENTS.md is missing or dangles, so Codex reads nothing \(clone ~/github/agents, then run: ic-link\)' \
  "fails on a dangling ~/AGENTS.md rather than accepting its target as the fallback"
assert_not_grep "$section" 'FAIL  ~/AGENTS.md[^(]*\(run: ic-link\)$' \
  "does not offer a bare 'run: ic-link', which is what created the dangling link"

# --- the same dangling link with the agents repo cloned, where ic-link is the fix ---
home=$(new_home agents-md-dangling-with-repo)
plant_wiring "$home"
rm "$home/.claude/CLAUDE.md"
ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  ~/AGENTS.md is missing or dangles, so Codex reads nothing \(run: ic-link\)' \
  "offers ic-link for a dangling ~/AGENTS.md once there is a manual to point it at"

# --- the repo cloned, but bin/build-manuals never run, so there is still no target ---
home=$(new_home agents-md-dangling-no-manuals)
plant_wiring "$home"
rm "$home/github/agents/AGENTS.md" "$home/github/agents/CLAUDE.md"
ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  ~/AGENTS.md is missing or dangles, so Codex reads nothing \(run: ~/github/agents/bin/build-manuals, then ic-link\)' \
  "names build-manuals when the repo is cloned but no manual is generated to point at"
assert_not_grep "$section" 'FAIL  ~/AGENTS.md[^(]*\(run: ic-link\)$' \
  "does not offer a bare 'run: ic-link' when rerunning it would recreate the dangling link"

# --- Claude's manual is not a substitute for the neutral one the link needs ---
home=$(new_home agents-md-dangling-claude-manual-only)
plant_wiring "$home"
rm "$home/github/agents/AGENTS.md" "$home/.claude/CLAUDE.md"
ln -sfn ".claude/CLAUDE.md" "$home/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  ~/AGENTS.md is missing or dangles, so Codex reads nothing \(run: ~/github/agents/bin/build-manuals, then ic-link\)' \
  "names build-manuals when only Claude's manual is generated, since ic-link cannot make a neutral one"

# --- skip when Gemini is not installed ---
home=$(new_home gemini-absent)
plant_wiring "$home"
section=$(run_section7 "$home")
assert_grep "$section" 'warn  gemini not set up \(~/.gemini absent\); skipping' \
  "skips Gemini checks when ~/.gemini is absent"
assert_not_grep "$section" 'FAIL  gemini' \
  "does not FAIL gemini checks when ~/.gemini is absent"

# --- healthy Gemini wiring ---
home=$(new_home gemini-healthy)
plant_wiring "$home"
plant_gemini "$home"
section=$(run_section7 "$home")
assert_grep "$section" 'ok    gemini: ~/.gemini/AGENTS.md -> agents/GEMINI.md' \
  "accepts ~/.gemini/AGENTS.md linked to Gemini's own manual"
assert_grep "$section" 'ok    gemini: context.fileName lists AGENTS.md' \
  "accepts a settings.json whose context.fileName lists AGENTS.md"
assert_grep "$section" 'ok    GEMINI.md declares the default development system' \
  "checks the routing section in the manual Gemini loads, as it does for the other three"
assert_not_grep "$section" 'FAIL  gemini' \
  "does not FAIL gemini checks when the manual is linked and actually loaded"
assert_not_grep "$section" 'FAIL  GEMINI' \
  "does not FAIL GEMINI.md when it declares the default development system"

# --- the manual Gemini loads has lost the routing section ---
home=$(new_home gemini-manual-no-routing)
plant_wiring "$home"
plant_gemini "$home"
printf '%s\n' '# Gemini operating manual' >"$home/github/agents/GEMINI.md"
section=$(run_section7 "$home")
assert_grep "$section" "FAIL  GEMINI.md missing the 'Default development system' section" \
  "fails when the manual Gemini loads no longer routes work through firstmate"
assert_grep "$section" 'ok    gemini: ~/.gemini/AGENTS.md -> agents/GEMINI.md' \
  "still reports the link itself as healthy, since only the manual's content regressed"

# --- Gemini's own memory file must stay a real file ---
home=$(new_home gemini-memory-symlinked)
plant_wiring "$home"
plant_gemini "$home"
ln -sfn "$home/github/agents/GEMINI.md" "$home/.gemini/GEMINI.md"
section=$(run_section7 "$home")
assert_grep "$section" "FAIL  gemini: ~/.gemini/GEMINI.md is a symlink; it is Gemini's own memory file and must stay a real file \(replace the link with a real file holding what it points at\)" \
  "fails when Gemini's memory file has been replaced with a symlink, naming the fix"

# --- manual not linked ---
home=$(new_home gemini-manual-unlinked)
plant_wiring "$home"
plant_gemini "$home"
rm "$home/.gemini/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  gemini: ~/.gemini/AGENTS.md is missing or not a symlink to ~/github/agents/GEMINI\.md \(run: ic-link\)' \
  "fails naming the source when ~/.gemini/AGENTS.md is not linked"

# --- a hand-made link at another tool's manual is a FAIL in every state ---
home=$(new_home gemini-claude-pointer)
plant_wiring "$home"
plant_gemini "$home"
ln -sfn "$home/.claude/CLAUDE.md" "$home/.gemini/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" "FAIL  gemini: ~/.gemini/AGENTS.md points at $home/.claude/CLAUDE\.md, not ~/github/agents/GEMINI\.md \(run: ic-link\)" \
  "fails naming Claude's manual as the target when ~/.gemini/AGENTS.md points at it"
assert_line_count "$section" 'FAIL .*\.gemini/AGENTS\.md' 1 \
  "a mislinked ~/.gemini/AGENTS.md yields exactly one FAIL line"

# --- and is still a FAIL with no agents repo, the state every hand-made link is in ---
home=$(new_home gemini-claude-pointer-no-repo)
mkdir -p "$home/.gemini" "$home/.claude"
printf '%s\n' '# Claude operating manual' '## Default development system' >"$home/.claude/CLAUDE.md"
ln -sfn "$home/.claude/CLAUDE.md" "$home/.gemini/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" "FAIL  gemini: ~/.gemini/AGENTS.md points at $home/.claude/CLAUDE\.md, not ~/github/agents/GEMINI\.md \(clone ~/github/agents, then run: ic-link\)" \
  "names Claude's manual as the target, and the clone to do first, when ~/github/agents is absent"
assert_not_grep "$section" 'gemini.*bin/build-manuals' \
  "does not name a build script that is not on disk until the repo is cloned"
assert_not_grep "$section" 'gemini.*manual not linked' \
  "does not also claim no manual is linked, when the wrong one is"
assert_grep "$section" 'warn  gemini: private agents repo not cloned \(~/github/agents\); manual not checked' \
  "says what was not checked rather than asserting a link state"

# --- a hand-made link at the manual a missing repo would provide ---
home=$(new_home gemini-dangling-no-repo)
mkdir -p "$home/.gemini"
printf '%s\n' '## Gemini Added Memories' >"$home/.gemini/GEMINI.md"
ln -sfn "$home/github/agents/GEMINI.md" "$home/.gemini/AGENTS.md"
section=$(run_section7 "$home")
assert_grep "$section" 'warn  gemini: ~/.gemini/AGENTS.md points at ~/github/agents/GEMINI.md, which does not exist until the private agents repo is cloned' \
  "reports a dangling hand-made link rather than falling silent about Gemini"
assert_line_count "$section" '(ok|warn|FAIL)  gemini' 1 \
  "says exactly one thing about Gemini in that state"

# --- agents repo present but missing the Gemini source ---
home=$(new_home gemini-no-manual-source)
plant_wiring "$home"
plant_gemini "$home"
rm "$home/github/agents/GEMINI.md"
section=$(run_section7 "$home")
assert_grep "$section" "FAIL  gemini: $home/github/agents/GEMINI\.md missing, so there is no manual to link \(run: ~/github/agents/bin/build-manuals, then ic-link\)" \
  "names build-manuals, since GEMINI.md is generated and must not be hand-written"
assert_line_count "$section" 'FAIL  gemini' 1 \
  "a missing GEMINI.md source yields exactly one Gemini FAIL line"

# --- the link alone is not enough: Gemini reads only the listed filenames ---
home=$(new_home gemini-settings-without-agents-md)
plant_wiring "$home"
plant_gemini "$home"
printf '%s\n' '{"context": {"fileName": ["GEMINI.md"]}}' >"$home/.gemini/settings.json"
section=$(run_section7 "$home")
assert_grep "$section" 'FAIL  gemini: ~/.gemini/settings.json context.fileName does not list AGENTS.md, so the linked manual is never loaded \(add "AGENTS.md" to context.fileName by hand; ic-link never writes settings.json, which is Gemini.s own file\)' \
  "fails naming the hand step, since ic-link deliberately never writes settings.json"

# --- Gemini installed, private agents repo not cloned ---
home=$(new_home gemini-no-agents-repo)
mkdir -p "$home/.gemini"
printf '%s\n' '{"context": {"fileName": ["GEMINI.md"]}}' >"$home/.gemini/settings.json"
section=$(run_section7 "$home")
assert_line_count "$section" 'warn  gemini: private agents repo not cloned \(~/github/agents\); manual not checked' 1 \
  "warns once when Gemini is installed but ~/github/agents is not cloned"
assert_not_grep "$section" 'FAIL  gemini' \
  "does not blame context.fileName on a fresh Gemini install with no manual to load"

# --- and the same with the settings file Gemini has not written yet ---
home=$(new_home gemini-no-agents-repo-no-settings)
mkdir -p "$home/.gemini"
section=$(run_section7 "$home")
assert_line_count "$section" 'warn  gemini: private agents repo not cloned \(~/github/agents\); manual not checked' 1 \
  "warns once when Gemini is installed with no settings.json at all"
assert_not_grep "$section" 'FAIL  gemini' \
  "does not FAIL on a missing settings.json when no manual is linked"

# --- a missing manual source must not draw a second FAIL about loading it ---
home=$(new_home gemini-no-manual-source-fresh-settings)
plant_wiring "$home"
plant_gemini "$home"
rm "$home/github/agents/GEMINI.md" "$home/.gemini/settings.json"
section=$(run_section7 "$home")
assert_line_count "$section" 'FAIL  gemini' 1 \
  "names only the missing GEMINI.md source, never context.fileName, when nothing is linked"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "ic_doctor_test: all checks passed"
  exit 0
fi
echo "ic_doctor_test: $FAILS failure(s)"
exit 1
