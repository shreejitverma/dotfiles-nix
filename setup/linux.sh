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
    --help|-h) echo "Usage: bash setup/linux.sh --profile <shreejitverma@linux|shreejitverma@wsl|...>"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[ -n "$HM_PROFILE" ] || die "No --profile given. Run setup/install.sh instead, which detects it for you."

# Which entry module backs this profile. Both the placeholder check and the
# checkout-path guard below read the module that will actually be activated.
case "$HM_PROFILE" in
  *@wsl|*@wsl-aarch64) ENTRY_MODULE="$DOTFILES_DIR/nix/wsl-user.nix"; IS_WSL=1 ;;
  *@linux|*@linux-aarch64) ENTRY_MODULE="$DOTFILES_DIR/nix/linux-user.nix"; IS_WSL=0 ;;
  *) die "Unknown profile '$HM_PROFILE'. Expected one of: shreejitverma@linux, shreejitverma@linux-aarch64, shreejitverma@wsl, shreejitverma@wsl-aarch64." ;;
esac

# Fail early if placeholder values have not been customized yet.
if grep -R -n -E 'yourname|/Users/yourname|/home/yourname|Your Name|you@example.com' \
  "$DOTFILES_DIR/flake.nix" \
  "$DOTFILES_DIR/nix" >/dev/null 2>&1; then
  echo "Placeholder values are still present in the repo."
  echo "Please replace values like 'yourname', '/home/yourname', 'Your Name', and 'you@example.com' before running setup/linux.sh."
  exit 1
fi

# Fail early if this checkout is not where the entry module says it is. Same
# reasoning as the guard in setup/mac.sh: mkOutOfStoreSymlink does not require
# its target to exist, so a checkout at any other path activates with a zero
# exit status and silently leaves the files/bin PATH entry, the zsh workflow
# layer, the linked app configs, and the sync-forks timer all dangling.
# Tolerant of an entry module whose literal it cannot parse: an unreadable
# literal skips the guard rather than blocking the bootstrap.
declared_rel=$(sed -n 's/.*dotfilesDir = "${config\.home\.homeDirectory}\([^"]*\)".*/\1/p' \
  "$ENTRY_MODULE" 2>/dev/null | head -1 || true)
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

# Install Nix via Determinate if missing.
if ! command -v nix &> /dev/null; then
  # The installer's default Linux plan registers the Nix daemon as a systemd
  # service, which fails wherever systemd is not PID 1. That is not just WSL
  # (systemd is opt-in there via /etc/wsl.conf): it also covers containers and
  # distros that use another init. Key the decision off what PID 1 actually is
  # rather than off WSL specifically, and ask for the init-less plan when there
  # is no systemd to register with.
  if [ "$(ps -p 1 -o comm= 2>/dev/null | tr -d ' ' || echo unknown)" != "systemd" ]; then
    echo "==> no systemd as PID 1: installing Nix with --init none"
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
HOME_MANAGER_BACKUP_EXT="${HOME_MANAGER_BACKUP_EXT:-backup}" \
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
echo "Bootstrap complete. Restart your shell, then use 'rebuild' for future config changes."
if [ "$IS_WSL" -eq 1 ]; then
  echo "Note: the weekly fork sync timer is not enabled on WSL, because systemd is off by default there."
  echo "Run 'syncforks' by hand, or enable systemd in /etc/wsl.conf."
fi
