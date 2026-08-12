#!/bin/bash
#
# End-to-end test of the Linux and WSL profiles: a real Nix build and a real
# Home Manager activation inside a Linux container.
#
# tests/install_dispatch_test.sh proves the installer *decides* correctly, using
# stubs. This proves the decision actually *works*: it activates the profile for
# real and then asserts on the environment that comes out the other side.
#
# What it does not cover: the Determinate installer itself. The container image
# already has Nix, so the `if ! command -v nix` branch of setup/linux.sh is
# skipped. That branch is deliberately not exercised against a real host,
# exactly as setup/mac.sh's installer branch is not; see tests/README.md.
#
# Requires Docker. Skips (exit 0) when Docker is unavailable, so it can sit in a
# test suite on machines that cannot run it.
#
# Run: bash tests/linux_e2e_docker.sh

set -uo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)
IMAGE="${IC_E2E_IMAGE:-nixos/nix:latest}"

FAILURES=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "SKIP: Docker is not available; the Linux end-to-end test needs it."
  exit 0
fi

STAGE=$(cd -P -- "$(mktemp -d "${TMPDIR:-/tmp}/ic-e2e.XXXXXX")" && pwd)
cleanup() { [ -n "${DEBUG_KEEP_SANDBOX:-}" ] || rm -rf "$STAGE"; }
trap cleanup EXIT

# Stage the working tree, not HEAD: this must test the code as it is right now,
# including changes that are not committed yet. .git is excluded so the flake is
# treated as a plain path, which also sidesteps Nix's "not tracked by git" error
# for files that have not been added.
tar -C "$REPO_ROOT" --exclude .git --exclude .no-mistakes -cf - . | tar -C "$STAGE" -xf -

assert_in() {
  local haystack="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then pass "$msg"; else
    fail "$msg -- expected: $needle"
  fi
}

run_profile() {
  local target="$1"
  docker run --rm -v "$STAGE:/src:ro" "$IMAGE" bash -c '
set -euo pipefail
mkdir -p /home/shreejitverma/github/dotfiles-nix /home/shreejitverma/.nvm
cp -r /src/. /home/shreejitverma/github/dotfiles-nix/
export HOME=/home/shreejitverma USER=shreejitverma
export NIX_CONFIG="experimental-features = nix-command flakes"
cd /home/shreejitverma/github/dotfiles-nix
bash setup/install.sh --target '"$target"' --yes >/tmp/install.log 2>&1 || { echo "INSTALL_FAILED"; tail -25 /tmp/install.log; exit 1; }
echo "INSTALL_OK"

# Verification runs without -e on purpose. The image is minimal, and under -e a
# single missing utility aborts the script and every remaining probe silently
# reports as a failure, which points at the config rather than at the tool that
# was actually absent.
set +e
export PATH="$HOME/.nix-profile/bin:$PATH"
for b in rg fd bat eza zoxide atuin starship delta jq home-manager; do
  command -v "$b" >/dev/null && echo "BIN_OK $b" || echo "BIN_MISSING $b"
done
echo "REBUILD_ALIAS $(grep -o "alias -- rebuild=.*" "$HOME/.zshrc" || echo none)"

# Ordering matters: ic-workflow.zsh must come after the tool integrations and
# before zsh-syntax-highlighting, which upstream requires to load last. Done
# with grep and parameter expansion because this image has no awk or cut.
line_of() {
  local match; match=$(grep -n "$1" "$HOME/.zshrc" 2>/dev/null | head -1)
  echo "${match%%:*}"
}
echo "ORDER $(line_of "atuin init") $(line_of "ic-workflow.zsh") $(line_of "zsh-syntax-highlighting.zsh")"

# The distro login shell is bash, so the session PATH and the aliases have to
# survive a bash login too, not only the generated zshrc.
bash -lc "printenv PATH" 2>/dev/null | grep -q "dotfiles-nix/files/bin" && echo BASH_PATH_OK || echo BASH_PATH_MISSING
grep -q "alias -- rebuild=" "$HOME/.bashrc" && echo BASH_ALIAS_OK || echo BASH_ALIAS_MISSING

[ -e "$HOME/.config/systemd/user/timers.target.wants/sync-forks.timer" ] && echo "TIMER_ENABLED" || echo "TIMER_NOT_ENABLED"
[ -e "$HOME/.config/fontconfig" ] && echo "DESKTOP_YES" || echo "DESKTOP_NO"
grep -q "alias -- open=explorer.exe" "$HOME/.zshrc" && echo "WSL_ALIASES" || echo "NO_WSL_ALIASES"
exit 0
' 2>&1
}

echo "=== linux profile ==="
out=$(run_profile linux)
assert_in "$out" "INSTALL_OK" "linux: install completes"
assert_in "$out" "REBUILD_ALIAS alias -- rebuild='home-manager switch" "linux: rebuild drives home-manager, not darwin-rebuild"
assert_in "$out" "@linux" "linux: rebuild alias names a linux profile"
assert_in "$out" "TIMER_ENABLED" "linux: the daily sync timer is enabled"
assert_in "$out" "DESKTOP_YES" "linux: the desktop layer is present"
assert_in "$out" "NO_WSL_ALIASES" "linux: WSL interop aliases are absent"
assert_in "$out" "BASH_PATH_OK" "linux: a bash login gets files/bin on PATH"
assert_in "$out" "BASH_ALIAS_OK" "linux: bash inherits the zsh alias set, rebuild included"
for b in rg fd bat eza zoxide atuin starship delta jq home-manager; do
  assert_in "$out" "BIN_OK $b" "linux: $b is installed"
done
if order=$(grep -o 'ORDER [0-9]* [0-9]* [0-9]*' <<<"$out"); then
  read -r _ a w s <<<"$order"
  if [ -n "$a" ] && [ -n "$w" ] && [ -n "$s" ] && [ "$a" -lt "$w" ] && [ "$w" -lt "$s" ]; then
    pass "linux: zshrc order is atuin($a) < ic-workflow($w) < syntax-highlighting($s)"
  else
    fail "linux: zshrc order wrong -- atuin=$a ic-workflow=$w syntax-highlighting=$s"
  fi
else
  fail "linux: could not read zshrc ordering"
fi

echo
echo "=== wsl profile ==="
out=$(run_profile wsl)
assert_in "$out" "INSTALL_OK" "wsl: install completes"
assert_in "$out" "@wsl" "wsl: rebuild alias names a wsl profile"
assert_in "$out" "TIMER_NOT_ENABLED" "wsl: the sync timer is left disabled, since systemd is off by default"
assert_in "$out" "DESKTOP_NO" "wsl: the desktop layer is omitted"
assert_in "$out" "WSL_ALIASES" "wsl: Windows interop aliases are present"
assert_in "$out" "BASH_PATH_OK" "wsl: a bash login gets files/bin on PATH"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$FAILURES check(s) failed." >&2
fi
exit $(( FAILURES > 0 ))
