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

# Stubs for the two binaries that could reach the outside world: the Determinate
# installer download and every real `nix` invocation. Both announce themselves on
# stderr and fail, so any case that gets far enough to call one stops there and
# says so in the captured output, instead of running for real. Every invocation
# of setup/linux.sh below leads its PATH with this directory: a masked-down
# PATH of /usr/bin:/bin is not enough on its own, because a stock macOS or Linux
# host has a real curl sitting in it.
NOINSTALL="$SANDBOX/stubs-noinstall"
mkdir -p "$NOINSTALL"
guard_write_path "$NOINSTALL/curl"
printf '#!/bin/bash\necho "STUB_CURL_CALLED $*" >&2\nexit 1\n' >"$NOINSTALL/curl"
guard_write_path "$NOINSTALL/nix"
printf '#!/bin/bash\necho "STUB_NIX_CALLED $*" >&2\nexit 1\n' >"$NOINSTALL/nix"
chmod +x "$NOINSTALL/curl" "$NOINSTALL/nix"

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

# An architecture the flake has no output for used to fall through to the
# x86_64 profile, so the run installed Nix and only then died inside `nix build`
# with a system mismatch pointing nowhere near the cause.
RISCV=$(make_uname_stub riscv Linux riscv64)
out=$(run_install "$RISCV" "$PLAIN_PROC" "$EMPTY")
assert_contains "$out" "Unsupported CPU architecture" "an unsupported architecture is rejected, not mapped to x86_64"
assert_contains "$out" "riscv64" "the architecture error names the uname -m it saw"
assert_contains "$out" "aarch64" "the architecture error names what is supported"
assert_not_contains "$out" "command: bash" "nothing is dispatched on an unsupported architecture"

status=$(run_install "$RISCV" "$PLAIN_PROC" "$EMPTY" >/dev/null 2>&1; echo $?)
if [ "$status" -ne 0 ]; then pass "an unsupported architecture exits non-zero"
else fail "an unsupported architecture exits non-zero -- got $status"; fi

# --- dry-run really is inert -------------------------------------------------

out=$(run_install "$LINUX_X86" "$PLAIN_PROC" "$EMPTY")
assert_contains "$out" "dry-run: nothing was installed." "--dry-run says it installed nothing"

# --- linux.sh rejects a profile it has no entry module for -------------------

out=$(env -i HOME="$SANDBOX/home" PATH="$NOINSTALL:/usr/bin:/bin" \
  "$REAL_BASH" "$REPO_ROOT/setup/linux.sh" --profile nonsense </dev/null 2>&1)
assert_contains "$out" "Unknown profile 'nonsense'" "linux.sh rejects an unknown profile"

out=$(env -i HOME="$SANDBOX/home" PATH="$NOINSTALL:/usr/bin:/bin" \
  "$REAL_BASH" "$REPO_ROOT/setup/linux.sh" </dev/null 2>&1)
assert_contains "$out" "No --profile given" "linux.sh refuses to guess when given no profile"

# --- linux.sh refuses a checkout that is not where its entry module says ------
# This is what stops a WSL install from running against a /mnt/c checkout, whose
# absolute links would resolve only while the Windows drive is mounted. The
# fixture sits at a deliberately wrong path, so the guard must fire; PATH leads
# with the failing curl and nix stubs so that even if the guard ever regressed,
# the rest of the script has no way to reach a real installer or a real build.
FIXTURE="$SANDBOX/wrong-place/dotfiles-nix"
mkdir -p "$FIXTURE/nix/home" "$FIXTURE/setup/lib" "$SANDBOX/home"
for f in nix/linux-user.nix nix/wsl-user.nix nix/user.nix nix/host.nix \
         nix/home/dotfiles.nix nix/home/common.nix nix/home/desktop.nix \
         nix/home/darwin.nix nix/home/linux.nix nix/home/wsl.nix \
         setup/linux.sh setup/install.sh setup/lib/platform.sh flake.nix; do
  guard_write_path "$FIXTURE/$f"
  cp "$REPO_ROOT/$f" "$FIXTURE/$f"
done

for profile in shreejitverma@linux shreejitverma@wsl; do
  out=$(env -i HOME="$SANDBOX/home" PATH="$NOINSTALL:/usr/bin:/bin" \
    "$REAL_BASH" "$FIXTURE/setup/linux.sh" --profile "$profile" </dev/null 2>&1)
  status=$?
  assert_contains "$out" "declares dotfilesDir=" "linux.sh ($profile) refuses a checkout at the wrong path"
  assert_contains "$out" "$SANDBOX/home/github/dotfiles-nix" "linux.sh ($profile) names the declared path"
  assert_not_contains "$out" "building" "linux.sh ($profile) never reaches the build step"
  assert_not_contains "$out" "STUB_CURL_CALLED" "linux.sh ($profile) never reaches the Nix installer"
  assert_not_contains "$out" "STUB_NIX_CALLED" "linux.sh ($profile) never invokes nix at the wrong path"
  [ "$status" -ne 0 ] && pass "linux.sh ($profile) exits non-zero at the wrong path" \
    || fail "linux.sh ($profile) exits non-zero at the wrong path -- got $status"
done

# --- and the guard survives a userland with no sed ---------------------------
# The guard used to read the dotfilesDir literal by shelling out to sed. Where
# sed is absent the answer came back empty and the check was skipped outright,
# silently re-enabling exactly the misinstall it exists to prevent. PATH here is
# masked down to the three binaries the guard path legitimately needs, so sed
# (and awk, and everything else) is genuinely gone, and the guard must still
# fire on the same wrongly-placed fixture.
NOSED="$SANDBOX/stubs-nosed"
mkdir -p "$NOSED"
for b in dirname basename grep; do
  guard_write_path "$NOSED/$b"
  ln -sf "$(command -v "$b")" "$NOSED/$b"
done
if [ -e "$NOSED/sed" ]; then
  fail "the sed-free PATH still has sed on it -- the test below would prove nothing"
else
  out=$(env -i HOME="$SANDBOX/home" PATH="$NOSED" \
    "$REAL_BASH" "$FIXTURE/setup/linux.sh" --profile shreejitverma@linux </dev/null 2>&1)
  status=$?
  assert_contains "$out" "declares dotfilesDir=" "the checkout guard still fires with sed off PATH"
  assert_not_contains "$out" "command not found" "the guard does not reach for a binary the userland lacks"
  [ "$status" -ne 0 ] && pass "linux.sh exits non-zero at the wrong path with sed off PATH" \
    || fail "linux.sh exits non-zero at the wrong path with sed off PATH -- got $status"
fi


# --- linux.sh refuses to activate over a startup file it cannot back up ------
# Home Manager backs up a regular file it has to replace, but its collision
# check skips the backup for a symlink, so a symlinked ~/.bashrc would abort
# activation with "would be clobbered" only after the whole build had run. The
# guard has to fire before any of that. The fixture sits at the path the entry
# module declares, so the checkout guard above passes and this one is what
# stops the run; PATH leads with the stub curl and nix, which fail loudly, so
# reaching the Determinate installer or a build would show up as an assertion
# failure rather than as a real download.
GOOD_HOME="$SANDBOX/home-symlink"
GOOD_FIXTURE="$GOOD_HOME/github/dotfiles-nix"
mkdir -p "$GOOD_FIXTURE/nix/home" "$GOOD_FIXTURE/setup/lib"
for f in nix/linux-user.nix nix/wsl-user.nix nix/user.nix nix/host.nix \
         nix/home/dotfiles.nix nix/home/common.nix nix/home/desktop.nix \
         nix/home/darwin.nix nix/home/linux.nix nix/home/wsl.nix \
         setup/linux.sh setup/install.sh setup/lib/platform.sh flake.nix; do
  guard_write_path "$GOOD_FIXTURE/$f"
  cp "$REPO_ROOT/$f" "$GOOD_FIXTURE/$f"
done
# A real file is backed up, so it is announced and the run continues; a symlink
# out of a personal dotfiles checkout is the case that has to stop.
guard_write_path "$GOOD_HOME/elsewhere-bashrc"
printf 'export PS1="mine> "\n' >"$GOOD_HOME/elsewhere-bashrc"
guard_write_path "$GOOD_HOME/.bashrc"
ln -sfn "$GOOD_HOME/elsewhere-bashrc" "$GOOD_HOME/.bashrc"
guard_write_path "$GOOD_HOME/.profile"
printf '# distro default\n' >"$GOOD_HOME/.profile"

out=$(env -i HOME="$GOOD_HOME" PATH="$NOINSTALL:/usr/bin:/bin" \
  "$REAL_BASH" "$GOOD_FIXTURE/setup/linux.sh" --profile shreejitverma@linux </dev/null 2>&1)
status=$?
assert_contains "$out" "$GOOD_HOME/.bashrc" "linux.sh names the symlinked startup file it cannot back up"
assert_contains "$out" "mv $GOOD_HOME/.bashrc $GOOD_HOME/.bashrc.pre-home-manager" \
  "linux.sh gives the exact command to move it aside"
assert_not_contains "$out" "building" "linux.sh never reaches the build step"
assert_not_contains "$out" "STUB_CURL_CALLED" "linux.sh never reaches the Nix installer"
[ "$status" -ne 0 ] && pass "linux.sh exits non-zero on an unbackupable startup file" \
  || fail "linux.sh exits non-zero on an unbackupable startup file -- got $status"

# With the symlink gone, the regular ~/.profile is announced rather than blocking.
rm -f "$GOOD_HOME/.bashrc"
out=$(env -i HOME="$GOOD_HOME" PATH="$NOINSTALL:/usr/bin:/bin" \
  "$REAL_BASH" "$GOOD_FIXTURE/setup/linux.sh" --profile shreejitverma@linux </dev/null 2>&1)
assert_contains "$out" "kept as $GOOD_HOME/.profile.backup" \
  "linux.sh announces the regular startup file it will back up"
assert_not_contains "$out" "Home Manager backs up a regular file" \
  "linux.sh does not block on a regular startup file"

# --- the profile name is derived from flake.nix, not restated ----------------
# A fork replaces `username` in flake.nix and nothing else, which is what
# README step 2 tells it to do. The profile names have to follow, or the run
# installs Nix and only then dies on a homeConfigurations attribute that does
# not exist. This fixture's flake declares a different user, so every answer
# below has to come from the file rather than from a constant in the shell.
ALT_HOME="$SANDBOX/home-altuser"
ALT_FIXTURE="$ALT_HOME/github/dotfiles-nix"
mkdir -p "$ALT_FIXTURE/nix/home" "$ALT_FIXTURE/setup/lib"
for f in nix/linux-user.nix nix/wsl-user.nix nix/user.nix nix/host.nix \
         nix/home/dotfiles.nix nix/home/common.nix nix/home/desktop.nix \
         nix/home/darwin.nix nix/home/linux.nix nix/home/wsl.nix \
         setup/linux.sh setup/install.sh setup/lib/platform.sh flake.nix; do
  guard_write_path "$ALT_FIXTURE/$f"
  cp "$REPO_ROOT/$f" "$ALT_FIXTURE/$f"
done
guard_write_path "$ALT_FIXTURE/flake.nix"
cat >"$ALT_FIXTURE/flake.nix" <<'EOF'
{
  outputs = { ... }:
    let
      username = "alice";
    in
    { inherit username; };
}
EOF

out=$(env -i HOME="$ALT_HOME" PATH="$LINUX_X86:/usr/bin:/bin" \
  WSL_OSRELEASE_FILE="$PLAIN_PROC" WSL_VERSION_FILE="$EMPTY" \
  "$REAL_BASH" "$ALT_FIXTURE/setup/install.sh" --dry-run </dev/null 2>&1)
assert_contains "$out" "profile: alice@linux" "install.sh derives the profile name from the flake's username literal"
assert_not_contains "$out" "profile: shreejitverma@linux" "install.sh does not fall back to a restated username"

out=$(env -i HOME="$ALT_HOME" PATH="$NOINSTALL:/usr/bin:/bin" \
  "$REAL_BASH" "$ALT_FIXTURE/setup/linux.sh" --profile shreejitverma@linux </dev/null 2>&1)
status=$?
assert_contains "$out" 'flake.nix declares username = "alice"' \
  "linux.sh rejects a profile the flake's username does not build, naming the real cause"
assert_not_contains "$out" "STUB_CURL_CALLED" "linux.sh rejects the stale profile before installing Nix"
assert_not_contains "$out" "STUB_NIX_CALLED" "linux.sh rejects the stale profile before invoking nix"
[ "$status" -ne 0 ] && pass "linux.sh exits non-zero on a profile the flake does not define" \
  || fail "linux.sh exits non-zero on a profile the flake does not define -- got $status"

# The matching accept case, and the only one in this suite that clears every
# guard: the fixture sits at its declared path and ALT_HOME has no startup files,
# so the run carries on into the Nix half of the script. That is exactly why the
# stub `nix` matters here rather than being left to the stub curl and pipefail to
# stop by accident: with a real nix anywhere on PATH the installer branch is
# skipped outright and the next step is a genuine `nix flake lock` and build
# against the fixture. The stub is reached, announces itself, and fails, so the
# assertions can say where the run stopped instead of only what it did not print.
out=$(env -i HOME="$ALT_HOME" PATH="$NOINSTALL:/usr/bin:/bin" \
  "$REAL_BASH" "$ALT_FIXTURE/setup/linux.sh" --profile alice@linux </dev/null 2>&1)
assert_not_contains "$out" "Unknown profile" "linux.sh accepts the profile the flake's username does build"
assert_contains "$out" "STUB_NIX_CALLED" \
  "the accepted profile clears the profile, checkout-path and startup-file guards"
assert_contains "$out" "flake lock" "the accepted profile stops at the stubbed nix, before any build"
assert_not_contains "$out" "==> building" "the accepted profile never reaches the build step"
assert_not_contains "$out" "==> activating" "the accepted profile never reaches activation"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$FAILURES check(s) failed." >&2
fi
exit $(( FAILURES > 0 ))
