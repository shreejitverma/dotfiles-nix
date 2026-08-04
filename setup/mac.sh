#!/bin/bash

set -euo pipefail

DOTFILES_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && cd .. && pwd )

# Fail early if placeholder values have not been customized yet
if grep -R -n -E 'yourname|/Users/yourname|Your Name|you@example.com' \
  "$DOTFILES_DIR/flake.nix" \
  "$DOTFILES_DIR/nix" >/dev/null 2>&1; then
  echo "Placeholder values are still present in the repo."
  echo "Please replace values like 'yourname', '/Users/yourname', 'Your Name', and 'you@example.com' before running setup/mac.sh."
  exit 1
fi

# Fail early if this checkout is not where nix/user.nix says it is. Everything
# the activation wires into the machine (the files/bin PATH entry, the zsh
# workflow layer, the out-of-store app config symlinks, the sync-forks launchd
# agent) is built from the dotfilesDir literal, and mkOutOfStoreSymlink does
# not require its target to exist, so a checkout at any other path activates
# with a zero exit status and leaves every one of those dangling. Checked here,
# before anything mutates the machine. Tolerant of a nix/user.nix this can't
# parse: an unreadable literal skips the guard rather than blocking bootstrap.
declared_rel=$(sed -n 's/.*dotfilesDir = "${config\.home\.homeDirectory}\([^"]*\)".*/\1/p' \
  "$DOTFILES_DIR/nix/user.nix" 2>/dev/null | head -1 || true)
if [ -n "$declared_rel" ]; then
  declared_dir="$HOME$declared_rel"
  resolved_checkout=$(cd -P -- "$DOTFILES_DIR" && pwd)
  resolved_declared=""
  if [ -d "$declared_dir" ]; then
    resolved_declared=$(cd -P -- "$declared_dir" && pwd)
  fi
  if [ "$resolved_declared" != "$resolved_checkout" ]; then
    echo "This checkout is at $resolved_checkout, but nix/user.nix declares dotfilesDir=$declared_dir."
    echo "Activating from here would leave the linked app configs, the files/bin PATH entry, the zsh workflow layer, and the sync-forks agent all pointing at a path that does not exist."
    echo "Either clone this repo to $declared_dir, or edit dotfilesDir in nix/user.nix to match $resolved_checkout."
    exit 1
  fi
fi

# Install Nix via Determinate if missing
if ! command -v nix &> /dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

  # The installer wires Nix into new shells, but this script is still running
  # in the shell that started before Nix existed. Source the daemon profile
  # now so `nix` works for the rest of this run instead of needing a second
  # session. The profile script isn't written to be `set -u` safe, so relax
  # that guard just around the source. (Overridable so tests can point at a
  # sandboxed profile instead of the real one.)
  : "${NIX_DAEMON_PROFILE:=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
  if [ -f "$NIX_DAEMON_PROFILE" ]; then
    set +u
    # shellcheck disable=SC1090
    . "$NIX_DAEMON_PROFILE"
    set -u
  fi
fi

# Install Homebrew if missing
if ! command -v brew &> /dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Resolve nix by absolute path once, for every use below. PATH resolution can
# still fail here even after a successful install (a relocated or missing
# daemon profile means the source above was skipped), and sudo would not
# inherit the sourced PATH anyway.
NIX_BIN=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)

# Generate the flake lock as the current user first, so the sudo rebuild
# below doesn't create a root-owned flake.lock inside your repo.
if [ ! -f "$DOTFILES_DIR/flake.lock" ]; then
  "$NIX_BIN" --extra-experimental-features 'nix-command flakes' \
    flake lock "$DOTFILES_DIR"
fi

# Apply the Nix configuration. (DARWIN_REBUILD_BIN is overridable so tests
# can point at a sandboxed binary instead of the real one.)
: "${DARWIN_REBUILD_BIN:=/run/current-system/sw/bin/darwin-rebuild}"
if [ -x "$DARWIN_REBUILD_BIN" ]; then
  sudo "$DARWIN_REBUILD_BIN" switch --flake "$DOTFILES_DIR#mac"
else
  # First activation: nix-darwin has never run, so darwin-rebuild doesn't
  # exist yet and has to be fetched via `nix run`. Uses the absolute $NIX_BIN
  # resolved above since sudo won't inherit the PATH this script just sourced,
  # and enables the experimental features it needs in case nix.conf doesn't
  # already have them.
  sudo "$NIX_BIN" --extra-experimental-features "nix-command flakes" \
    run nix-darwin/master#darwin-rebuild -- switch --flake "$DOTFILES_DIR#mac"
fi

# Install nvm and a default Node.js if missing
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
fi

echo "Bootstrap complete. Restart your shell if needed, then use 'rebuild' or darwin-rebuild for future config changes."
