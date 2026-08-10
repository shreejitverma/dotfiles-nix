#!/bin/bash
#
# platform.sh: shared platform detection, sourced rather than executed.
#
# The single source of truth for "what kind of machine is this and which flake
# output installs it". setup/install.sh, files/bin/up, and files/bin/ic-doctor
# all source this, so the answer cannot drift between the installer, the update
# command, and the health check.
#
# Every function is prefixed ic_ because callers source this into their own
# namespace.

# Overridable so tests can point the WSL probes at fixture files instead of the
# real /proc. Normal use should leave these unset.
: "${WSL_OSRELEASE_FILE:=/proc/sys/kernel/osrelease}"
: "${WSL_VERSION_FILE:=/proc/version}"

# The user the flake declares. Kept here so the profile names below stay in step
# with flake.nix if the placeholder is ever replaced.
: "${IC_FLAKE_USER:=shreejitverma}"

ic_is_wsl() {
  # WSL sets these in every shell it starts. The /proc probes are the fallback
  # for when the environment has been scrubbed, as in a service or `env -i`.
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  [ -n "${WSL_INTEROP:-}" ] && return 0
  grep -qiE 'microsoft|wsl' "$WSL_OSRELEASE_FILE" 2>/dev/null && return 0
  grep -qiE 'microsoft|wsl' "$WSL_VERSION_FILE" 2>/dev/null && return 0
  return 1
}

ic_detect_target() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) echo darwin ;;
    Linux) if ic_is_wsl; then echo wsl; else echo linux; fi ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

ic_detect_arch() {
  case "$(uname -m 2>/dev/null || echo unknown)" in
    arm64|aarch64) echo aarch64 ;;
    x86_64|amd64) echo x86_64 ;;
    *) echo unknown ;;
  esac
}

# Maps a target plus an architecture onto the flake output that installs it.
# macOS has exactly one system configuration; Linux and WSL are per-architecture
# Home Manager profiles, and picking the wrong one would rebuild for the wrong
# CPU, so the architecture is part of the name.
ic_profile_for() {
  local target="$1" arch="$2"
  case "$target" in
    darwin) echo "darwinConfigurations.mac" ;;
    linux) if [ "$arch" = aarch64 ]; then echo "${IC_FLAKE_USER}@linux-aarch64"; else echo "${IC_FLAKE_USER}@linux"; fi ;;
    wsl) if [ "$arch" = aarch64 ]; then echo "${IC_FLAKE_USER}@wsl-aarch64"; else echo "${IC_FLAKE_USER}@wsl"; fi ;;
    *) return 1 ;;
  esac
}

# Where long-lived logs belong. macOS has ~/Library/Logs; Linux has no such
# convention, so this follows the XDG state directory instead of inventing a
# Library folder that nothing else on the system would look in.
ic_log_dir() {
  if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    echo "$HOME/Library/Logs"
  else
    echo "${XDG_STATE_HOME:-$HOME/.local/state}"
  fi
}

# Desktop notification, best effort. Never fails the caller: these run from
# launchd and systemd timers where there may be no session to notify at all.
ic_notify() {
  local title="$1" message="$2"
  case "$(uname -s 2>/dev/null)" in
    Darwin)
      osascript -e "display notification \"$message\" with title \"$title\"" >/dev/null 2>&1 || true
      ;;
    *)
      if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message" >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

# A PATH that works under the minimal environment launchd and systemd hand to
# timers, where the user's shell profile has never been sourced.
ic_default_path() {
  if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    echo "$HOME/.local/bin:/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$HOME/go/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  else
    echo "$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  fi
}

ic_describe() {
  case "$1" in
    darwin) echo "macOS - nix-darwin + Home Manager (manages the whole machine)" ;;
    linux) echo "Linux - standalone Home Manager (user environment only)" ;;
    wsl) echo "WSL - standalone Home Manager, no desktop layer" ;;
    windows) echo "native Windows - not a Nix target; use WSL2" ;;
    *) echo "unknown platform" ;;
  esac
}
