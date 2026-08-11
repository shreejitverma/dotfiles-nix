#!/bin/bash
#
# sync_forks_test.sh: end-to-end regression test for files/bin/sync-forks.
#
# Runs the real script against sandboxed $HOME directories containing real git
# repositories wired to local bare "origin" and "upstream" remotes, so every
# fetch, fast-forward, and push is a genuine git operation with observable
# state. Nothing touches the network or the real machine: the script's PATH
# (built by ic_default_path) leads with the sandbox's ~/.local/bin, where stub
# gh / osascript / notify-send executables record their invocations instead of
# calling GitHub or posting notifications. The stubs also read stdin, so a
# regression that drops the deliberate </dev/null redirects inside the
# manifest while-read loop surfaces as later manifest entries being slurped
# and never processed.
#
# Honours DEBUG_KEEP_SANDBOX=1 to leave the scratch directory on disk.
set -uo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && cd .. && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/sync-forks-test.XXXXXX")"
REMOTES="$SANDBOX/remotes"
mkdir -p "$REMOTES" "$SANDBOX/seed"

cleanup() {
  if [ "${DEBUG_KEEP_SANDBOX:-0}" = "1" ]; then
    echo "DEBUG_KEEP_SANDBOX=1: sandbox left at $SANDBOX"
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

# Fixture git operations must not read the invoking user's real config
# (a host-level commit.gpgsign or hook path would break commits).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

FAILS=0
ok()   { printf 'ok: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; FAILS=$((FAILS + 1)); }

assert_grep() { # file pattern description
  if grep -q "$2" "$1" 2>/dev/null; then ok "$3"; else fail "$3 (no match for '$2' in $1)"; fi
}
assert_not_grep() { # file pattern description
  if grep -q "$2" "$1" 2>/dev/null; then fail "$3 (unexpected match for '$2' in $1)"; else ok "$3"; fi
}
assert_eq() { # actual expected description
  if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (got '$1', want '$2')"; fi
}
assert_file() { # file description
  if [ -f "$1" ]; then ok "$2"; else fail "$2 ($1 missing)"; fi
}
assert_no_file() { # file description
  if [ -f "$1" ]; then fail "$2 ($1 exists)"; else ok "$2"; fi
}

gcommit() { # dir message
  git -C "$1" -c user.name='Fixture' -c user.email='fixture@example.com' commit -q -m "$2"
}

# A sandboxed $HOME with the correct global identity and recording stubs ahead
# of everything else on the PATH sync-forks builds for itself.
new_home() { # name -> prints path
  local home="$SANDBOX/home-$1"
  mkdir -p "$home/.local/bin" "$home/github/.fleet" "$home/.config"
  printf '[user]\n\tname = Shreejit Verma\n\temail = shreejitverma@gmail.com\n' >"$home/.gitconfig"
  cat >"$home/.local/bin/gh" <<'EOF'
#!/bin/bash
cat >/dev/null
printf 'gh %s\n' "$*" >>"$HOME/gh-calls.log"
EOF
  cat >"$home/.local/bin/osascript" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOME/notifications.log"
EOF
  cp "$home/.local/bin/osascript" "$home/.local/bin/notify-send"
  chmod +x "$home/.local/bin/gh" "$home/.local/bin/osascript" "$home/.local/bin/notify-send"
  printf '%s\n' "$home"
}

# A fork fixture: bare upstream and origin remotes plus a local clone under
# $home/github/<name>, optionally <ahead> local-only commits and <behind>
# upstream-only commits.
make_fork() { # name behind ahead home
  local name="$1" behind="$2" ahead="$3" home="$4"
  local seed="$SANDBOX/seed/$name" up="$REMOTES/$name-up.git" or="$REMOTES/$name-or.git"
  local clone="$home/github/$name" i
  git init -q -b main "$seed"
  echo base >"$seed/f.txt"
  git -C "$seed" add -A && gcommit "$seed" "base"
  git clone -q --bare "$seed" "$up"
  git clone -q --bare "$seed" "$or"
  git clone -q "$or" "$clone"
  git -C "$clone" remote add upstream "$up"
  for ((i = 1; i <= ahead; i++)); do
    echo "local$i" >>"$clone/local.txt"
    git -C "$clone" add -A && gcommit "$clone" "local $i"
  done
  for ((i = 1; i <= behind; i++)); do
    echo "up$i" >>"$seed/up.txt"
    git -C "$seed" add -A && gcommit "$seed" "up $i"
  done
  [ "$behind" -gt 0 ] && git -C "$seed" push -q "$up" main
  return 0
}

run_sync() { # home [args...]
  local home="$1"
  shift
  env -u GIT_CONFIG_GLOBAL -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL \
    -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u EMAIL \
    HOME="$home" XDG_CONFIG_HOME="$home/.config" USER="${USER:-tester}" \
    GIT_CONFIG_NOSYSTEM=1 \
    bash "$REPO_ROOT/files/bin/sync-forks" "$@"
}

sha() { git -C "$1" rev-parse "${2:-main}"; }

TODAY="$(date +%Y%m%d)"

# =============================================================================
# Scenario group A: the main manifest-driven run.
# alpha-behind      2 behind, install command   -> ff, push, reinstall, synced
# bravo-uptodate    up to date, local identity override, install command
#                                               -> override stripped, no install
# charlie-diverged  1 ahead + 1 behind          -> DIVERGED, untouched
# delta-dirty       1 behind, dirty tree        -> skipped
# echo-branch       1 behind, on feature branch -> skipped
# foxtrot-nosync    sync: false                 -> never mentioned
# golf-missing      in manifest, not cloned     -> skipped
# Expected notification: exactly one, "diverged" (no failures).
# =============================================================================
echo "== scenario A: manifest-driven sync run =="
HOME_A="$(new_home a)"
make_fork alpha-behind 2 0 "$HOME_A"
make_fork bravo-uptodate 0 0 "$HOME_A"
git -C "$HOME_A/github/bravo-uptodate" config user.email stale@university.edu
git -C "$HOME_A/github/bravo-uptodate" config user.name "Stale Name"
make_fork charlie-diverged 1 1 "$HOME_A"
make_fork delta-dirty 1 0 "$HOME_A"
echo dirty >>"$HOME_A/github/delta-dirty/f.txt"
make_fork echo-branch 1 0 "$HOME_A"
git -C "$HOME_A/github/echo-branch" checkout -q -b feature
make_fork foxtrot-nosync 1 0 "$HOME_A"

cat >"$HOME_A/github/.fleet/manifest.yaml" <<EOF
fleet:
  root: ~/github
repos:
- name: alpha-behind
  default_branch: main
  sync: true
  install: "cat >/dev/null && touch \$HOME/alpha-installed"
- name: bravo-uptodate
  sync: true
  install: "touch \$HOME/bravo-installed"
- name: charlie-diverged
  sync: true
- name: delta-dirty
  sync: true
- name: echo-branch
  sync: true
- name: foxtrot-nosync
  sync: false
- name: golf-missing
  sync: true
EOF

# Log rotation fixtures: a 40-day-old daily log must be deleted, a fresh one kept.
mkdir -p "$HOME_A/github/.fleet/logs"
touch "$HOME_A/github/.fleet/logs/sync-20200101.log"
touch -t 202001010000 "$HOME_A/github/.fleet/logs/sync-20200101.log"
touch "$HOME_A/github/.fleet/logs/sync-fresh.log"

CHARLIE_BEFORE="$(sha "$HOME_A/github/charlie-diverged")"
CHARLIE_ORIGIN_BEFORE="$(sha "$REMOTES/charlie-diverged-or.git")"
DELTA_BEFORE="$(sha "$HOME_A/github/delta-dirty")"
FOX_ORIGIN_BEFORE="$(sha "$REMOTES/foxtrot-nosync-or.git")"

run_sync "$HOME_A" >"$SANDBOX/run-a.out" 2>&1
assert_eq "$?" 0 "A: sync-forks exits 0"

LOG_A="$HOME_A/github/.fleet/logs/sync-$TODAY.log"
assert_file "$LOG_A" "A: daily log created under ~/github/.fleet/logs"
assert_no_file "$HOME_A/github/.fleet/logs/sync-20200101.log" "A: 40-day-old log rotated away"
assert_file "$HOME_A/github/.fleet/logs/sync-fresh.log" "A: recent log kept by rotation"

# alpha: fast-forwarded to upstream, pushed to the fork, reinstalled.
ALPHA_UP="$(sha "$REMOTES/alpha-behind-up.git")"
assert_eq "$(sha "$HOME_A/github/alpha-behind")" "$ALPHA_UP" "A: alpha local main fast-forwarded to upstream head"
assert_eq "$(sha "$REMOTES/alpha-behind-or.git")" "$ALPHA_UP" "A: alpha fork origin pushed to upstream head"
assert_grep "$LOG_A" '\[alpha-behind\] fast-forwarded 2 commit' "A: alpha logged as fast-forwarded"
assert_file "$HOME_A/alpha-installed" "A: alpha install command re-ran after update"
assert_grep "$LOG_A" '\[alpha-behind\] reinstalled' "A: alpha reinstall logged"

# bravo: up to date -> install must NOT run; local identity override stripped.
assert_no_file "$HOME_A/bravo-installed" "A: bravo install NOT run without an update"
assert_grep "$LOG_A" '\[bravo-uptodate\] already up to date' "A: bravo already up to date"
assert_grep "$LOG_A" '\[bravo-uptodate\] removing local user.email override (stale@university.edu)' "A: bravo stale local user.email logged"
if git -C "$HOME_A/github/bravo-uptodate" config --local user.email >/dev/null 2>&1; then
  fail "A: bravo local user.email override removed"
else
  ok "A: bravo local user.email override removed"
fi
if git -C "$HOME_A/github/bravo-uptodate" config --local user.name >/dev/null 2>&1; then
  fail "A: bravo local user.name override removed"
else
  ok "A: bravo local user.name override removed"
fi

# charlie: diverged -> reported and left completely untouched.
assert_grep "$LOG_A" '\[charlie-diverged\] DIVERGED: 1 local, 1 upstream' "A: charlie reported DIVERGED"
assert_eq "$(sha "$HOME_A/github/charlie-diverged")" "$CHARLIE_BEFORE" "A: charlie local branch untouched"
assert_eq "$(sha "$REMOTES/charlie-diverged-or.git")" "$CHARLIE_ORIGIN_BEFORE" "A: charlie fork origin untouched"

# delta and echo: skipped, unmodified.
assert_grep "$LOG_A" '\[delta-dirty\] working tree dirty -> skipped' "A: delta dirty tree skipped"
assert_eq "$(sha "$HOME_A/github/delta-dirty")" "$DELTA_BEFORE" "A: delta branch untouched"
assert_grep "$LOG_A" "\\[echo-branch\\] on 'feature', not default 'main' -> skipped" "A: echo on feature branch skipped"
assert_eq "$(git -C "$HOME_A/github/echo-branch" symbolic-ref --short HEAD)" feature "A: echo still on feature branch"

# foxtrot (sync: false): never processed. golf: not cloned, skipped.
assert_not_grep "$LOG_A" 'foxtrot-nosync' "A: sync:false repo never mentioned"
assert_eq "$(sha "$REMOTES/foxtrot-nosync-or.git")" "$FOX_ORIGIN_BEFORE" "A: sync:false fork origin untouched"
assert_grep "$LOG_A" '\[golf-missing\] not cloned, skip' "A: uncloned repo skipped"

# gh repo sync: pinned to the branch, only for forks with no local-only commits.
assert_grep "$HOME_A/gh-calls.log" '^gh repo sync shreejitverma/alpha-behind -b main$' "A: gh repo sync called for alpha"
assert_grep "$HOME_A/gh-calls.log" '^gh repo sync shreejitverma/bravo-uptodate -b main$' "A: gh repo sync called for bravo"
assert_not_grep "$HOME_A/gh-calls.log" 'charlie-diverged' "A: gh repo sync NOT called for diverged fork"

# Summary and notification: diverged only -> one "diverged forks" notification.
assert_grep "$LOG_A" 'synced:\[ alpha-behind bravo-uptodate \]' "A: summary lists synced repos"
assert_grep "$LOG_A" 'failed:\[ \]' "A: summary shows no failures"
assert_eq "$(wc -l <"$HOME_A/notifications.log" | tr -d ' ')" 1 "A: exactly one notification"
assert_grep "$HOME_A/notifications.log" 'sync-forks: diverged forks' "A: diverged notification fired"
assert_grep "$HOME_A/notifications.log" 'charlie-diverged' "A: diverged notification names the fork"

# =============================================================================
# Scenario group B: failures escalate over divergence.
# hotel-noupstream  cloned without an upstream remote -> failed, not "up to date"
# india-diverged    diverged                          -> reported
# Expected notification: "failures" (failure outranks divergence).
# =============================================================================
echo "== scenario B: failure escalation =="
HOME_B="$(new_home b)"
make_fork hotel-noupstream 0 0 "$HOME_B"
git -C "$HOME_B/github/hotel-noupstream" remote remove upstream
make_fork india-diverged 1 1 "$HOME_B"
cat >"$HOME_B/github/.fleet/manifest.yaml" <<EOF
- name: hotel-noupstream
  sync: true
- name: india-diverged
  sync: true
EOF

run_sync "$HOME_B" >"$SANDBOX/run-b.out" 2>&1
assert_eq "$?" 0 "B: sync-forks exits 0"
LOG_B="$HOME_B/github/.fleet/logs/sync-$TODAY.log"
assert_grep "$LOG_B" '\[hotel-noupstream\] no upstream/main after fetch' "B: missing upstream remote is a failure, not up-to-date"
assert_grep "$LOG_B" '\[india-diverged\] DIVERGED' "B: diverged fork still reported"
assert_eq "$(wc -l <"$HOME_B/notifications.log" | tr -d ' ')" 1 "B: exactly one notification"
assert_grep "$HOME_B/notifications.log" 'sync-forks: failures' "B: failure notification outranks diverged"
assert_grep "$HOME_B/notifications.log" 'hotel-noupstream' "B: failure notification names the repo"

# =============================================================================
# Scenario group C: host without a fleet manifest -> logs and exits 0 quietly.
# =============================================================================
echo "== scenario C: no manifest =="
HOME_C="$(new_home c)"
rm -rf "$HOME_C/github/.fleet"
run_sync "$HOME_C" >"$SANDBOX/run-c.out" 2>&1
assert_eq "$?" 0 "C: exits 0 without a manifest"
assert_grep "$SANDBOX/run-c.out" 'no fleet manifest at .* nothing to sync' "C: says nothing to sync"
assert_no_file "$HOME_C/notifications.log" "C: no notification without a manifest"

# =============================================================================
# Scenario group D: --dry-run reports drift and mutates nothing.
# =============================================================================
echo "== scenario D: dry run =="
HOME_D="$(new_home d)"
make_fork juliet-behind 2 0 "$HOME_D"
cat >"$HOME_D/github/.fleet/manifest.yaml" <<EOF
- name: juliet-behind
  sync: true
  install: "touch \$HOME/juliet-installed"
EOF
JULIET_BEFORE="$(sha "$HOME_D/github/juliet-behind")"
JULIET_ORIGIN_BEFORE="$(sha "$REMOTES/juliet-behind-or.git")"

run_sync "$HOME_D" --dry-run >"$SANDBOX/run-d.out" 2>&1
assert_eq "$?" 0 "D: dry run exits 0"
LOG_D="$HOME_D/github/.fleet/logs/sync-$TODAY.log"
assert_grep "$LOG_D" '\[juliet-behind\] behind=2 ahead=0' "D: dry run reports drift"
assert_eq "$(sha "$HOME_D/github/juliet-behind")" "$JULIET_BEFORE" "D: dry run leaves local branch untouched"
assert_eq "$(sha "$REMOTES/juliet-behind-or.git")" "$JULIET_ORIGIN_BEFORE" "D: dry run leaves fork origin untouched"
assert_no_file "$HOME_D/juliet-installed" "D: dry run does not reinstall"
assert_no_file "$HOME_D/gh-calls.log" "D: dry run never calls gh"

# =============================================================================
# Scenario group E: a stray global identity (stale email) fails the repo
# instead of syncing with the wrong author, and fires the failure notification.
# =============================================================================
echo "== scenario E: wrong resolved identity =="
HOME_E="$(new_home e)"
printf '[user]\n\tname = Old Student\n\temail = stale@university.edu\n' >"$HOME_E/.gitconfig"
make_fork kilo-behind 1 0 "$HOME_E"
cat >"$HOME_E/github/.fleet/manifest.yaml" <<EOF
- name: kilo-behind
  sync: true
EOF
KILO_BEFORE="$(sha "$HOME_E/github/kilo-behind")"
KILO_ORIGIN_BEFORE="$(sha "$REMOTES/kilo-behind-or.git")"

run_sync "$HOME_E" >"$SANDBOX/run-e.out" 2>&1
assert_eq "$?" 0 "E: exits 0 (per-repo failure is non-fatal)"
LOG_E="$HOME_E/github/.fleet/logs/sync-$TODAY.log"
assert_grep "$LOG_E" '\[kilo-behind\] ERROR: author identity does not resolve to shreejitverma@gmail.com' "E: wrong identity fails the repo"
assert_eq "$(sha "$HOME_E/github/kilo-behind")" "$KILO_BEFORE" "E: repo left untouched on identity failure"
assert_eq "$(sha "$REMOTES/kilo-behind-or.git")" "$KILO_ORIGIN_BEFORE" "E: fork origin untouched on identity failure"
assert_grep "$HOME_E/notifications.log" 'sync-forks: failures' "E: failure notification fired"

# =============================================================================
# Scenario group F: ic-workflow.zsh sources the generated fleet aliases.
# =============================================================================
echo "== scenario F: fleet aliases hook =="
if command -v zsh >/dev/null 2>&1; then
  HOME_F="$(new_home f)"
  cat >"$HOME_F/github/.fleet/aliases.zsh" <<'EOF'
fleet-status() { echo fleet-status-ok; }
EOF
  OUT_F="$(env HOME="$HOME_F" zsh -fc "source '$REPO_ROOT/files/zsh/ic-workflow.zsh' >/dev/null 2>&1; fleet-status" 2>&1)"
  assert_eq "$OUT_F" "fleet-status-ok" "F: fleet-status from generated aliases.zsh available after sourcing ic-workflow.zsh"
  rm -f "$HOME_F/github/.fleet/aliases.zsh"
  if env HOME="$HOME_F" zsh -fc "source '$REPO_ROOT/files/zsh/ic-workflow.zsh' >/dev/null 2>&1"; then
    ok "F: ic-workflow.zsh still sources cleanly without aliases.zsh"
  else
    fail "F: ic-workflow.zsh failed to source without aliases.zsh"
  fi
else
  echo "skip: zsh not available, fleet aliases hook not tested"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "sync_forks_test: ALL PASS"
else
  echo "sync_forks_test: $FAILS FAILURE(S)"
  exit 1
fi
