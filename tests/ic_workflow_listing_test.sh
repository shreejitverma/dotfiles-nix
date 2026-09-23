#!/bin/bash
#
# ic_workflow_listing_test.sh: regression test for the eza listing commands in
# files/zsh/ic-workflow.zsh when stdin is not a terminal.
#
# eza reads file names from stdin whenever stdin is not a terminal and no path
# is given, so under agents, pipes, and scripts a bare `ls` listed nothing or
# blocked forever on an open stdin. The zsh layer must:
#   - make `ls` the system ls off a terminal, even when an older `ls=eza` alias
#     (as Home Manager's eza integration used to define) is already in place
#   - give every eza listing command an explicit `.` when called without a path,
#     and pass a path through untouched when one is given
#   - never block when stdin is an open pipe
#
# eza is replaced by a stub on PATH that reproduces exactly that stdin rule, so
# the suite needs no real eza and runs anywhere zsh does.
# Honours DEBUG_KEEP_SANDBOX=1.
#
# Run: bash tests/ic_workflow_listing_test.sh
set -uo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && cd .. && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/ic-workflow-listing-test.XXXXXX")"

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
assert_eq() {
  if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (got '$1', want '$2')"; fi
}

if ! command -v zsh >/dev/null 2>&1; then
  echo "ic_workflow_listing_test: zsh not available; skipping"
  exit 0
fi

# Stub eza: list the path arguments when there are any; otherwise read file
# names from stdin, which is what the real eza does off a terminal. Option
# values are not paths, so the stub skips them using the eza 0.23 option table.
mkdir -p "$SANDBOX/bin" "$SANDBOX/dir"
cat >"$SANDBOX/bin/eza" <<'EOF'
#!/bin/bash
paths=()
while [ $# -gt 0 ]; do
  a=$1
  shift
  case "$a" in
    --) paths+=("$@"); break ;;
    --level|--width|--ignore-glob|--sort|--time|--time-style|--color-scale-mode) shift ;;
    --classify|--color|--colour|--icons|--hyperlink|--color-scale)
      case "${1-}" in always|auto|never|all|age|size) shift ;; esac ;;
    --*) ;;
    -?*)
      c=${a#-}
      while [ -n "$c" ]; do
        case "$c" in
          [LwIst]) shift; break ;;
          [LwIst]*) break ;;
        esac
        c=${c#?}
      done ;;
    *) paths+=("$a") ;;
  esac
done
if [ "${#paths[@]}" -gt 0 ]; then
  printf 'EZA %s\n' "${paths[*]}"
else
  while IFS= read -r line; do printf 'STDIN %s\n' "$line"; done
fi
EOF
chmod +x "$SANDBOX/bin/eza"
touch "$SANDBOX/dir/alpha" "$SANDBOX/dir/beta"

# Run one command in a non-interactive zsh with the workflow layer sourced on
# top of the alias Home Manager's eza integration used to leave behind. The
# command goes through eval so it is parsed after the aliases exist, as it is
# for a command typed after the rc file has run. The caller supplies stdin.
run_zsh() { # <command>
  HOME="$SANDBOX" PATH="$SANDBOX/bin:/usr/bin:/bin" zsh -f -c '
    alias ls=eza
    source "$1" >/dev/null 2>&1
    cd "$2" || exit 1
    eval "$3"
  ' zsh "$REPO_ROOT/files/zsh/ic-workflow.zsh" "$SANDBOX/dir" "$1"
}

out=$(run_zsh 'whence -w ls' </dev/null)
assert_eq "$out" "ls: function" "ls is the workflow function even with an ls=eza alias already defined"

out=$(run_zsh 'ls' </dev/null | tr '\n' ' ')
assert_eq "$out" "alpha beta " "bare ls off a terminal lists the directory via the system ls"

out=$(run_zsh 'll' </dev/null)
assert_eq "$out" "EZA ." "bare ll hands eza an explicit '.' so it never reads stdin"

out=$(run_zsh 'lt' </dev/null)
assert_eq "$out" "EZA ." "bare lt hands eza an explicit '.'"

out=$(run_zsh 'll alpha' </dev/null)
assert_eq "$out" "EZA alpha" "an explicit path is passed through without an extra '.'"

# Option values are not paths: each of these must still get the default '.'.
for cmd in 'lt -L 3' 'lt -L3' 'lt --level 4' 'll --sort size' 'll -s modified' "ll -I '*.o'" 'll --color always'; do
  out=$(run_zsh "$cmd" </dev/null)
  assert_eq "$out" "EZA ." "'$cmd' hands eza an explicit '.' despite the option value"
done

out=$(run_zsh 'll -- -file' </dev/null)
assert_eq "$out" "EZA -file" "a path after '--' is passed through without an extra '.'"

# An open stdin that never delivers data or EOF: a FIFO held open by a writer
# that just sleeps. Timing only run_zsh, not the writer, is what shows a hang.
mkfifo "$SANDBOX/stdin.fifo"
sleep 30 >"$SANDBOX/stdin.fifo" &
writer=$!
start=$(date +%s)
out=$(run_zsh 'll' <"$SANDBOX/stdin.fifo")
elapsed=$(( $(date +%s) - start ))
kill "$writer" 2>/dev/null
wait "$writer" 2>/dev/null
assert_eq "$out" "EZA ." "ll with an open pipe on stdin still lists the directory"
if [ "$elapsed" -lt 30 ]; then
  ok "ll with an open pipe on stdin returns without waiting for the pipe (${elapsed}s)"
else
  fail "ll blocked on an open stdin pipe (${elapsed}s)"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "ic_workflow_listing_test: all checks passed"
  exit 0
fi
echo "ic_workflow_listing_test: $FAILS failure(s)"
exit 1
