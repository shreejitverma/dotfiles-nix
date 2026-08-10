#!/bin/bash
#
# Regression test for setup/install.sh and the platform detection it shares with
# files/bin/up and files/bin/ic-doctor.
#
# setup/install.sh ends in `exec` on a real bootstrap that installs Nix and
# activates a machine, so as with tests/mac_setup_test.sh it can never be run
# for real here. Two techniques keep this honest:
#
#   * --dry-run exercises the whole decision path (argument parsing, detection,
#     architecture mapping, profile selection, dispatch target) and stops
#     immediately before exec, printing the resolved plan.
#   * PATH is masked down to stub `uname` executables, so "what platform is
#     this" is something the test controls rather than something it inherits
#     from the machine it happens to run on. Without that, the WSL and Linux
#     cases could only ever be asserted from a Linux host.
#
# The WSL probes read $WSL_OSRELEASE_FILE / $WSL_VERSION_FILE, which the test
# points at fixture files instead of the real /proc.
#
# Run: bash tests/install_dispatch_test.sh

set -uo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)
REAL_BASH=$(command -v bash)

FAILURES=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then pass "$msg"; else
    fail "$msg -- expected to find: $needle"
    echo "--- actual output ---" >&2; echo "$haystack" >&2; echo "---" >&2
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then
    fail "$msg -- expected NOT to find: $needle"
  else pass "$msg"; fi
}

# Resolved with -P immediately: on macOS mktemp hands back /var/..., which is a
# symlink to /private/var/..., and the write guard below compares against
# resolved paths. Without this every legitimate write looks like an escape.
SANDBOX=$(cd -P -- "$(mktemp -d "${TMPDIR:-/tmp}/ic-install-test.XXXXXX")" && pwd)
cleanup() { [ -n "${DEBUG_KEEP_SANDBOX:-}" ] || rm -rf "$SANDBOX"; }
trap cleanup EXIT

# Refuses to write anywhere outside the sandbox, so a future edit that builds a
# path by traversal or symlink cannot quietly mutate the host.
guard_write_path() {
  local target="$1" resolved
  resolved=$(cd -P -- "$(dirname -- "$target")" 2>/dev/null && pwd)/$(basename -- "$target")
  case "$resolved" in
    "$SANDBOX"/*) : ;;
    *) echo "REFUSING to write outside the sandbox: $target -> $resolved" >&2; exit 1 ;;
  esac
}

# Builds a stub `uname` reporting the given kernel and machine, and returns a
# PATH with it in front. Everything the script legitimately needs (grep, sed,
# cat) still resolves through the real PATH appended behind the stub dir.
make_uname_stub() {
  local name="$1" kernel="$2" machine="$3"
  local dir="$SANDBOX/stubs-$name"
  mkdir -p "$dir"
  guard_write_path "$dir/uname"
  cat >"$dir/uname" <<EOF
#!/bin/bash
case "\${1:-}" in
  -s) echo "$kernel" ;;
  -m) echo "$machine" ;;
  *) echo "$kernel" ;;
esac
EOF
  chmod +x "$dir/uname"
  echo "$dir"
}

# Runs install.sh --dry-run under a stubbed uname and fixture /proc files.
# stdin is </dev/null so the interactive branch can never engage: a regression
# that prompts unconditionally shows up as a hang-free wrong answer, not as a
# test that blocks forever.
run_install() {
  local stubdir="$1" osrelease="$2" version="$3"; shift 3
  env -i \
    HOME="$SANDBOX/home" \
    PATH="$stubdir:/usr/bin:/bin:/usr/sbin:/sbin" \
    WSL_OSRELEASE_FILE="$osrelease" \
    WSL_VERSION_FILE="$version" \
    "$REAL_BASH" "$REPO_ROOT/setup/install.sh" --dry-run "$@" </dev/null 2>&1
}

mkdir -p "$SANDBOX/home"
EMPTY="$SANDBOX/empty"; guard_write_path "$EMPTY"; : >"$EMPTY"
WSL_PROC="$SANDBOX/osrelease-wsl"; guard_write_path "$WSL_PROC"
echo "5.15.153.1-microsoft-standard-WSL2" >"$WSL_PROC"
PLAIN_PROC="$SANDBOX/osrelease-plain"; guard_write_path "$PLAIN_PROC"
echo "6.8.0-generic" >"$PLAIN_PROC"

DARWIN_ARM=$(make_uname_stub darwin-arm Darwin arm64)
DARWIN_X86=$(make_uname_stub darwin-x86 Darwin x86_64)
LINUX_X86=$(make_uname_stub linux-x86 Linux x86_64)
LINUX_ARM=$(make_uname_stub linux-arm Linux aarch64)
WINDOWS=$(make_uname_stub windows MINGW64_NT-10.0 x86_64)

# --- detection ---------------------------------------------------------------

out=$(run_install "$DARWIN_ARM" "$EMPTY" "$EMPTY")
assert_contains "$out" "target:  darwin" "macOS is detected from uname -s"
assert_contains "$out" "profile: darwinConfigurations.mac" "macOS maps to the nix-darwin configuration"
assert_contains "$out" "setup/mac.sh" "macOS dispatches to mac.sh"
assert_not_contains "$out" "setup/linux.sh" "macOS never dispatches to linux.sh"

out=$(run_install "$LINUX_X86" "$PLAIN_PROC" "$EMPTY")
assert_contains "$out" "target:  linux" "plain Linux is detected as linux, not wsl"
assert_contains "$out" "profile: shreejitverma@linux" "x86_64 Linux maps to the x86_64 profile"
assert_contains "$out" "setup/linux.sh --profile shreejitverma@linux" "Linux dispatches to linux.sh with its profile"

# --- WSL is Linux plus a marker; each probe must be sufficient on its own -----

out=$(run_install "$LINUX_X86" "$WSL_PROC" "$EMPTY")
assert_contains "$out" "target:  wsl" "WSL is detected from /proc/sys/kernel/osrelease"
assert_contains "$out" "profile: shreejitverma@wsl" "WSL maps to the wsl profile, not the linux one"

out=$(run_install "$LINUX_X86" "$EMPTY" "$WSL_PROC")
assert_contains "$out" "target:  wsl" "WSL is detected from /proc/version when osrelease is clean"

out=$(env -i HOME="$SANDBOX/home" PATH="$LINUX_X86:/usr/bin:/bin" \
  WSL_DISTRO_NAME=Ubuntu WSL_OSRELEASE_FILE="$EMPTY" WSL_VERSION_FILE="$EMPTY" \
  "$REAL_BASH" "$REPO_ROOT/setup/install.sh" --dry-run </dev/null 2>&1)
assert_contains "$out" "target:  wsl" "WSL is detected from \$WSL_DISTRO_NAME with both /proc probes clean"

out=$(env -i HOME="$SANDBOX/home" PATH="$LINUX_X86:/usr/bin:/bin" \
  WSL_INTEROP=/run/WSL/8_interop WSL_OSRELEASE_FILE="$EMPTY" WSL_VERSION_FILE="$EMPTY" \
  "$REAL_BASH" "$REPO_ROOT/setup/install.sh" --dry-run </dev/null 2>&1)
assert_contains "$out" "target:  wsl" "WSL is detected from \$WSL_INTEROP with both /proc probes clean"

# --- architecture ------------------------------------------------------------
# The aarch64 profiles exist precisely so an ARM machine does not rebuild for
# x86_64, so this asserts the suffix rather than just "some linux profile".

out=$(run_install "$LINUX_ARM" "$PLAIN_PROC" "$EMPTY")
assert_contains "$out" "arch:    aarch64" "aarch64 is normalised from uname -m"
assert_contains "$out" "profile: shreejitverma@linux-aarch64" "ARM Linux selects the aarch64 profile"

out=$(run_install "$LINUX_ARM" "$WSL_PROC" "$EMPTY")
assert_contains "$out" "profile: shreejitverma@wsl-aarch64" "ARM WSL selects the aarch64 WSL profile"

out=$(run_install "$DARWIN_X86" "$EMPTY" "$EMPTY")
assert_contains "$out" "Intel Mac" "an Intel Mac is warned that the flake pins aarch64-darwin"

# --- explicit override beats detection ---------------------------------------

out=$(run_install "$DARWIN_ARM" "$EMPTY" "$EMPTY" --target linux)
assert_contains "$out" "target:  linux" "--target overrides detection"
assert_contains "$out" "setup/linux.sh" "--target linux dispatches to linux.sh even on macOS"

out=$(run_install "$LINUX_X86" "$WSL_PROC" "$EMPTY" --target linux)
assert_contains "$out" "profile: shreejitverma@linux" "--target linux overrides WSL detection"

# --- native Windows is refused, not half-installed ---------------------------

out=$(run_install "$WINDOWS" "$EMPTY" "$EMPTY")
assert_contains "$out" "no native Windows support" "a native Windows shell is told Nix cannot run there"
assert_contains "$out" "windows.ps1" "the Windows message points at the WSL bootstrap"
assert_not_contains "$out" "command: bash" "nothing is dispatched on native Windows"

status=$(run_install "$WINDOWS" "$EMPTY" "$EMPTY" >/dev/null 2>&1; echo $?)
[ "$status" -ne 0 ] && pass "native Windows exits non-zero" || fail "native Windows exits non-zero -- got $status"

# --- unknown platforms and bad input fail loudly -----------------------------

UNKNOWN=$(make_uname_stub unknown Haiku x86_64)
out=$(run_install "$UNKNOWN" "$EMPTY" "$EMPTY")
assert_contains "$out" "Could not identify this platform" "an unrecognised kernel is reported, not guessed at"

out=$(run_install "$DARWIN_ARM" "$EMPTY" "$EMPTY" --target bogus)
assert_contains "$out" "Unknown target 'bogus'" "an invalid --target is rejected"

# --- dry-run really is inert -------------------------------------------------

out=$(run_install "$LINUX_X86" "$PLAIN_PROC" "$EMPTY")
assert_contains "$out" "dry-run: nothing was installed." "--dry-run says it installed nothing"

# --- linux.sh rejects a profile it has no entry module for -------------------

out=$(env -i HOME="$SANDBOX/home" PATH="/usr/bin:/bin" \
  "$REAL_BASH" "$REPO_ROOT/setup/linux.sh" --profile nonsense </dev/null 2>&1)
assert_contains "$out" "Unknown profile 'nonsense'" "linux.sh rejects an unknown profile"

out=$(env -i HOME="$SANDBOX/home" PATH="/usr/bin:/bin" \
  "$REAL_BASH" "$REPO_ROOT/setup/linux.sh" </dev/null 2>&1)
assert_contains "$out" "No --profile given" "linux.sh refuses to guess when given no profile"

# --- linux.sh refuses a checkout that is not where its entry module says ------
# This is what stops a WSL install from running against a /mnt/c checkout, whose
# absolute links would resolve only while the Windows drive is mounted. The
# fixture sits at a deliberately wrong path, so the guard must fire; PATH is
# masked down to coreutils so that even if the guard ever regressed, there is no
# curl and no nix for the rest of the script to reach an installer with.
FIXTURE="$SANDBOX/wrong-place/dotfiles-nix"
mkdir -p "$FIXTURE/nix/home" "$FIXTURE/setup/lib" "$SANDBOX/home"
for f in nix/linux-user.nix nix/wsl-user.nix nix/user.nix nix/host.nix \
         nix/home/common.nix nix/home/desktop.nix nix/home/darwin.nix \
         nix/home/linux.nix nix/home/wsl.nix \
         setup/linux.sh setup/install.sh setup/lib/platform.sh flake.nix; do
  guard_write_path "$FIXTURE/$f"
  cp "$REPO_ROOT/$f" "$FIXTURE/$f"
done

for profile in shreejitverma@linux shreejitverma@wsl; do
  out=$(env -i HOME="$SANDBOX/home" PATH="/usr/bin:/bin" \
    "$REAL_BASH" "$FIXTURE/setup/linux.sh" --profile "$profile" </dev/null 2>&1)
  status=$?
  assert_contains "$out" "declares dotfilesDir=" "linux.sh ($profile) refuses a checkout at the wrong path"
  assert_contains "$out" "$SANDBOX/home/github/dotfiles-nix" "linux.sh ($profile) names the declared path"
  assert_not_contains "$out" "building" "linux.sh ($profile) never reaches the build step"
  [ "$status" -ne 0 ] && pass "linux.sh ($profile) exits non-zero at the wrong path" \
    || fail "linux.sh ($profile) exits non-zero at the wrong path -- got $status"
done

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$FAILURES check(s) failed." >&2
fi
exit $(( FAILURES > 0 ))
