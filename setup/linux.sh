#!/bin/bash
#
# linux.sh: bootstrap a Linux or WSL machine.
#
# The Linux counterpart of setup/mac.sh. The important difference is what it
# owns: on macOS, nix-darwin activates a whole system generation, whereas here
# there is no such thing for an existing distro, so this activates a standalone
# Home Manager generation and touches nothing outside the user's environment.
#
# Normally invoked through setup/install.sh, which detects the platform and
# passes the right --profile. It can also be run directly.
#
# Activation deliberately builds the activationPackage out of this flake and
# runs it, rather than `nix run home-manager/master -- switch`. That keeps the
# Home Manager doing the activation pinned to the same revision as flake.lock,
# instead of silently pulling a different one from the network.

set -euo pipefail

DOTFILES_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && cd .. && pwd )

# The flake-username and entry-module parsers are shared with setup/install.sh,
# setup/mac.sh, files/bin/ic-link and files/bin/ic-doctor, so none of them can
# drift in how it answers "which user, which checkout".
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/platform.sh
. "$DOTFILES_DIR/setup/lib/platform.sh"

# Overridable so the regression test can point these at a sandbox instead of the
# real filesystem. Normal use should leave them unset.
: "${NIX_DAEMON_PROFILE:=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
: "${DETERMINATE_INSTALLER_URL:=https://install.determinate.systems/nix}"
: "${NVM_INSTALL_URL:=https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh}"

# Deliberately not named PROFILE: the nvm installer at the end of this script
# reads a PROFILE environment variable, and reusing the name invites a collision.
HM_PROFILE=""

die() { echo "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) [ $# -ge 2 ] || die "--profile needs a value."; HM_PROFILE="$2"; shift 2 ;;
    --profile=*) HM_PROFILE="${1#*=}"; shift ;;
    --help|-h) echo "Usage: bash setup/linux.sh --profile <user>@<linux|linux-aarch64|wsl|wsl-aarch64>, where <user> is the username flake.nix declares."; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[ -n "$HM_PROFILE" ] || die "No --profile given. Run setup/install.sh instead, which detects it for you."

# Fail early if placeholder values have not been customized yet.
if grep -R -n -E 'yourname|/Users/yourname|/home/yourname|Your Name|you@example.com' \
  "$DOTFILES_DIR/flake.nix" \
  "$DOTFILES_DIR/nix" >/dev/null 2>&1; then
  echo "Placeholder values are still present in the repo."
  echo "Please replace values like 'yourname', '/home/yourname', 'Your Name', and 'you@example.com' before running setup/linux.sh."
  exit 1
fi

# The profile has to name an attribute flake.nix actually defines, and those
# names are built from the username literal there. Confirm it now, before Nix is
# installed: a fork that replaced the username in flake.nix alone would
# otherwise get all the way to `nix build` and fail on a missing attribute.
FLAKE_USER=$(ic_flake_user "$DOTFILES_DIR") || die "Could not read the username literal from $DOTFILES_DIR/flake.nix, so the profile name cannot be confirmed. Restore its 'username = \"...\";' line, or set IC_FLAKE_USER to the name it declares."

# Which entry module backs this profile. The checkout-path guard below reads the
# module that will actually be activated.
case "$HM_PROFILE" in
  "$FLAKE_USER@wsl"|"$FLAKE_USER@wsl-aarch64") ENTRY_MODULE="$DOTFILES_DIR/nix/wsl-user.nix"; IS_WSL=1 ;;
  "$FLAKE_USER@linux"|"$FLAKE_USER@linux-aarch64") ENTRY_MODULE="$DOTFILES_DIR/nix/linux-user.nix"; IS_WSL=0 ;;
  *) die "Unknown profile '$HM_PROFILE'. flake.nix declares username = \"$FLAKE_USER\", so the profiles it defines are: $FLAKE_USER@linux, $FLAKE_USER@linux-aarch64, $FLAKE_USER@wsl, $FLAKE_USER@wsl-aarch64." ;;
esac

# Fail early if this checkout is not where the entry module says it is. Same
# reasoning as the guard in setup/mac.sh: mkOutOfStoreSymlink does not require
# its target to exist, so a checkout at any other path activates with a zero
# exit status and silently leaves the files/bin PATH entry, the zsh workflow
# layer, the linked app configs, and the sync-forks timer all dangling.
# Tolerant of an entry module that declares no literal in the expected shape:
# that skips the guard rather than blocking the bootstrap. An entry module that
# cannot be read at all is a different condition and is reported, so the guard
# can never be disabled without a word about it.
declared_status=0
declared_rel=$(ic_declared_dotfiles_rel "$ENTRY_MODULE") || declared_status=$?
if [ "$declared_status" -eq 2 ]; then
  echo "warning: could not read $ENTRY_MODULE, so the checkout-path check is being skipped." >&2
fi
if [ -n "$declared_rel" ]; then
  declared_dir="$HOME$declared_rel"
  resolved_checkout=$(cd -P -- "$DOTFILES_DIR" && pwd)
  resolved_declared=""
  if [ -d "$declared_dir" ]; then
    resolved_declared=$(cd -P -- "$declared_dir" && pwd)
  fi
  if [ "$resolved_declared" != "$resolved_checkout" ]; then
    echo "This checkout is at $resolved_checkout, but $(basename "$ENTRY_MODULE") declares dotfilesDir=$declared_dir."
    echo "Activating from here would leave the files/bin PATH entry, the zsh workflow layer, the linked app configs, and the sync-forks timer all pointing at a path that does not exist."
    echo "Either clone this repo to $declared_dir, or edit dotfilesDir in $(basename "$ENTRY_MODULE") to match $resolved_checkout."
    exit 1
  fi
fi

# These profiles configure bash and zsh, so Home Manager owns the shell startup
# files and replaces any the machine already has. Classify them here, before
# anything is installed or built, because the two cases end very differently.
#
# A regular file is backed up, so it only needs announcing. A symlink is not:
# Home Manager's check-link-targets.sh gates both of its backup branches on the
# target not being a symlink, so HOME_MANAGER_BACKUP_EXT never applies to one,
# and activation aborts with an opaque "would be clobbered" only after the whole
# build has run. Symlinking a startup file out of a personal dotfiles checkout
# is a common state for someone adopting this repo, so stop up front with the
# path named instead. Broken symlinks are left out: Home Manager replaces those
# with `ln -Tsf` and never reaches a collision check, exactly as its own
# `-L && -e` classification implies.
#
# Detect, explain, abort. Nothing here moves or rewrites a user's file, and
# nothing waits for an answer: this script has to keep working under --yes, in
# CI, and over the stdin pipe setup/windows.ps1 uses.
HM_BACKUP_EXT="${HOME_MANAGER_BACKUP_EXT:-backup}"
hm_displaced=()
hm_blocking=()
for f in .bashrc .bash_profile .profile .zshrc .zshenv .zprofile; do
  p="$HOME/$f"
  if [ -L "$p" ] && [ -e "$p" ]; then
    # The same pattern Home Manager uses to recognise a link of its own.
    case "$(readlink "$p" 2>/dev/null || true)" in
      /nix/store/*-home-manager-files/*) ;;
      *) hm_blocking+=("$p") ;;
    esac
  elif [ ! -L "$p" ] && [ -e "$p" ]; then
    hm_displaced+=("$p")
  fi
done

if [ "${#hm_blocking[@]}" -gt 0 ]; then
  echo "These shell startup files are symlinks that Home Manager does not own:" >&2
  for p in "${hm_blocking[@]}"; do
    echo "  $p -> $(readlink "$p" 2>/dev/null || true)" >&2
  done
  echo >&2
  echo "Home Manager backs up a regular file it has to replace, but never a symlink," >&2
  echo "so activating now would fail partway through with 'would be clobbered'." >&2
  echo "Move each one aside, then re-run this script:" >&2
  for p in "${hm_blocking[@]}"; do
    echo "  mv $p $p.pre-home-manager" >&2
  done
  exit 1
fi

if [ "${#hm_displaced[@]}" -gt 0 ]; then
  echo
  echo "Note: this profile manages the shell startup files, so the following are about to"
  echo "become symlinks into the Nix store. Each original is preserved next to it:"
  for p in "${hm_displaced[@]}"; do
    echo "  $p  ->  kept as $p.$HM_BACKUP_EXT"
  done
  echo "Nothing is deleted; 'mv <file>.$HM_BACKUP_EXT <file>' puts one back."
  echo
fi

# Install Nix via Determinate if missing.
if ! command -v nix &> /dev/null; then
  # The installer's default Linux plan registers the Nix daemon as a systemd
  # service, which fails wherever systemd is not PID 1. That is not just WSL
  # (systemd is opt-in there via /etc/wsl.conf): it also covers containers and
  # distros that use another init. Key the decision off what PID 1 actually is
  # rather than off WSL specifically, and ask for the init-less plan when there
  # is no systemd to register with.
  #
  # /run/systemd/system is the canonical probe (it is what sd_booted(3) tests)
  # and needs no binaries at all. `ps` is only the fallback, and its output is
  # captured before it is compared, so a missing procps, which prints nothing,
  # stays distinguishable from a real answer of "not systemd". When the init
  # system cannot be determined at all, keep the default plan: a wrongly chosen
  # --init none leaves the nix-daemon unregistered and Nix unusable for the rest
  # of the run, which is the worse of the two failures.
  if [ -d /run/systemd/system ]; then
    init_system=systemd
  else
    # `|| true` is load-bearing under `set -o pipefail`: a missing ps makes the
    # pipeline exit non-zero, which would abort the script here rather than fall
    # through to the unknown case.
    init_system=$(ps -p 1 -o comm= 2>/dev/null | tr -d ' ' || true)
    [ -n "$init_system" ] || init_system=unknown
  fi

  if [ "$init_system" != systemd ] && [ "$init_system" != unknown ]; then
    echo "==> init is '$init_system', not systemd: installing Nix with --init none"
    curl --proto '=https' --tlsv1.2 -sSf -L "$DETERMINATE_INSTALLER_URL" \
      | sh -s -- install linux --init none --no-confirm
  else
    curl --proto '=https' --tlsv1.2 -sSf -L "$DETERMINATE_INSTALLER_URL" \
      | sh -s -- install --no-confirm
  fi

  # The installer wires Nix into new shells, but this script is still running in
  # the shell that started before Nix existed. Source the daemon profile now so
  # `nix` works for the rest of this run instead of needing a second session.
  # The profile script isn't written to be `set -u` safe, so relax that guard
  # just around the source.
  if [ -f "$NIX_DAEMON_PROFILE" ]; then
    set +u
    # shellcheck disable=SC1090
    . "$NIX_DAEMON_PROFILE"
    set -u
  fi
fi

# Resolve nix by absolute path once. PATH resolution can still fail here even
# after a successful install, if the daemon profile was relocated or missing and
# the source above was skipped.
NIX_BIN=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
NIX_FLAGS=(--extra-experimental-features 'nix-command flakes')

# Generate the flake lock first so activation does not have to.
if [ ! -f "$DOTFILES_DIR/flake.lock" ]; then
  "$NIX_BIN" "${NIX_FLAGS[@]}" flake lock "$DOTFILES_DIR"
fi

# Build the activation package from this flake, then run it. Unlike the macOS
# path there is no sudo here: standalone Home Manager writes only into $HOME and
# the per-user Nix profile.
echo "==> building $HM_PROFILE"
ACTIVATION_PACKAGE=$("$NIX_BIN" "${NIX_FLAGS[@]}" build \
  "$DOTFILES_DIR#homeConfigurations.\"$HM_PROFILE\".activationPackage" \
  --no-link --print-out-paths)

echo "==> activating $HM_PROFILE"
# Home Manager refuses to activate without a per-user Nix profile directory,
# and on a machine where this user has never run a nix command that directory
# does not exist yet ("Could not find suitable profile directory"). Create the
# XDG location it looks for first. Harmless when it already exists.
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles"

# Back up rather than fail when a real file is already sitting where Home
# Manager wants to write a symlink (a distro-provided ~/.zshrc, for example).
# The extension comes from the pre-flight above, so the one named in its notice
# is the one actually used, even when the caller overrides it.
HOME_MANAGER_BACKUP_EXT="$HM_BACKUP_EXT" \
  "$ACTIVATION_PACKAGE/activate"

# Install nvm and a default Node.js if missing, matching setup/mac.sh.
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  PROFILE=/dev/null bash -c "curl -o- $NVM_INSTALL_URL | bash"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
fi

echo
echo "Bootstrap complete. Open a new login shell (or run 'exec \$SHELL -l') to pick up"
echo "the new PATH and environment, then use 'rebuild' for future config changes."
if [ "${#hm_displaced[@]}" -gt 0 ]; then
  echo "Your previous shell startup files are the .$HM_BACKUP_EXT copies listed above;"
  echo "'mv <file>.$HM_BACKUP_EXT <file>' restores one until the next rebuild takes it over"
  echo "again. To keep something for good, put it in programs.bash.initExtra in nix/home/linux.nix."
fi

# Both bash and zsh get this repo's PATH, environment and aliases, so the line
# above is true whichever one the user logs in with. The zsh workflow layer in
# files/zsh is zsh-only, though, so point a bash login at the switch rather than
# leaving it to wonder why the workflow functions are missing. Only ever print
# the command: changing someone's login shell without being asked is not this
# script's call.
# getent rather than /etc/passwd: on a host using LDAP or SSSD the user has no
# passwd file entry, and getent is the only thing that resolves them. The shell
# is the last colon-separated field, extracted with a parameter expansion rather
# than sed, so a lean userland without sed degrades to the $SHELL fallback below
# instead of printing "sed: command not found" over an otherwise clean install.
passwd_entry=$(getent passwd "$(id -un)" 2>/dev/null || true)
login_shell="${passwd_entry##*:}"
[ -n "$login_shell" ] || login_shell="${SHELL:-}"
case "${login_shell##*/}" in
  zsh) ;;
  *)
    zsh_bin=$(command -v zsh 2>/dev/null || true)
    if [ -z "$zsh_bin" ] && [ -x "$HOME/.nix-profile/bin/zsh" ]; then
      zsh_bin="$HOME/.nix-profile/bin/zsh"
    fi
    echo
    echo "Your login shell is ${login_shell:-unknown}, not zsh. Everything above works in bash,"
    echo "but the zsh workflow layer (files/zsh/ic-workflow.zsh) only loads under zsh."
    if [ -n "$zsh_bin" ]; then
      echo "To switch:  chsh -s $zsh_bin"
      echo "If chsh refuses because that shell is not listed, add it first:"
      echo "  echo $zsh_bin | sudo tee -a /etc/shells"
    fi
    ;;
esac
if [ "$IS_WSL" -eq 1 ]; then
  echo "Note: the daily fork sync timer is not enabled on WSL, because systemd is off by default there."
  echo "Run 'syncforks' by hand, or enable systemd in /etc/wsl.conf."
fi
