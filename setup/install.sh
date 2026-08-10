#!/bin/bash
#
# install.sh: the single entry point for every platform.
#
# Detects whether this machine is macOS, a Linux distro, or a WSL distro, shows
# what it found, and dispatches to the matching bootstrap:
#
#   macOS       -> setup/mac.sh    (nix-darwin + Home Manager, owns the machine)
#   Linux, WSL  -> setup/linux.sh  (standalone Home Manager, user environment only)
#
# On an interactive terminal it confirms the detected target and lets you pick a
# different one. Non-interactively it uses the detection result without
# prompting, so it never hangs in CI or in a pipe. --target overrides detection
# outright.
#
# Native Windows is not a target: Nix has no native Windows support, so there is
# nothing for this script to install there. setup/windows.ps1 sets up WSL2 and
# then runs this script inside it.

set -euo pipefail

DOTFILES_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && cd .. && pwd )

# Platform detection is shared with files/bin/up and files/bin/ic-doctor so the
# installer, the update command, and the health check cannot disagree about what
# this machine is.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/platform.sh
. "$DOTFILES_DIR/setup/lib/platform.sh"

TARGET=""
ASSUME_YES=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash setup/install.sh [options]

Options:
  --target <darwin|linux|wsl>  Skip detection and install for this platform.
  --yes, -y                    Do not prompt; accept the detected target.
  --dry-run                    Print the resolved plan and exit without installing.
  --help, -h                   Show this help.

With no options on an interactive terminal, the detected target is shown and
confirmed before anything is installed.
EOF
}

die() { echo "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || die "--target needs a value (darwin, linux, or wsl)."; TARGET="$2"; shift 2 ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done

if [ -n "$TARGET" ]; then
  case "$TARGET" in
    darwin|linux|wsl) ;;
    *) die "Unknown target '$TARGET'. Valid targets are: darwin, linux, wsl." ;;
  esac
fi

ARCH=$(ic_detect_arch)
DETECTED=$(ic_detect_target)

if [ "$DETECTED" = windows ] && [ -z "$TARGET" ]; then
  cat >&2 <<EOF
This looks like a native Windows shell (MSYS, MinGW, or Cygwin).

Nix has no native Windows support, so there is nothing this script can install
here. Use WSL2 instead:

  powershell -ExecutionPolicy Bypass -File setup\\windows.ps1

That enables WSL2, installs a distro if you do not have one, and runs this same
script inside it. If you already have WSL2, open your distro and run:

  bash setup/install.sh
EOF
  exit 1
fi

if [ -z "$TARGET" ] && [ "$DETECTED" = unknown ]; then
  die "Could not identify this platform (uname -s = '$(uname -s 2>/dev/null || echo ?)'). Re-run with --target darwin|linux|wsl."
fi

# Interactive confirmation. Only when the user gave no explicit target, did not
# pass --yes, and stdin is a terminal that can actually answer.
if [ -z "$TARGET" ] && [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ] && [ -t 0 ]; then
  echo "Detected: $(ic_describe "$DETECTED")"
  echo
  echo "Install for:"
  echo "  1) macOS   $([ "$DETECTED" = darwin ] && echo '(detected)')"
  echo "  2) Linux   $([ "$DETECTED" = linux ] && echo '(detected)')"
  echo "  3) WSL     $([ "$DETECTED" = wsl ] && echo '(detected)')"
  echo "  q) quit"
  echo
  read -r -p "Choose [enter = detected]: " choice || choice=""
  case "$choice" in
    "") TARGET="$DETECTED" ;;
    1) TARGET=darwin ;;
    2) TARGET=linux ;;
    3) TARGET=wsl ;;
    q|Q) echo "Nothing was installed."; exit 0 ;;
    *) die "Unrecognised choice '$choice'. Nothing was installed." ;;
  esac
else
  TARGET="${TARGET:-$DETECTED}"
fi

if [ "$TARGET" = darwin ] && [ "$ARCH" = x86_64 ]; then
  echo "Note: flake.nix pins darwinConfigurations.mac to aarch64-darwin." >&2
  echo "On an Intel Mac, change that to x86_64-darwin before continuing." >&2
fi

PROFILE=$(ic_profile_for "$TARGET" "$ARCH")

case "$TARGET" in
  darwin) CMD=(bash "$DOTFILES_DIR/setup/mac.sh") ;;
  linux|wsl) CMD=(bash "$DOTFILES_DIR/setup/linux.sh" --profile "$PROFILE") ;;
esac

echo "target:  $TARGET"
echo "arch:    $ARCH"
echo "profile: $PROFILE"
echo "command: ${CMD[*]}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run: nothing was installed."
  exit 0
fi

exec "${CMD[@]}"
