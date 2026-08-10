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

# IC_FLAKE_USER is an escape hatch, deliberately unset by default. The username
# that builds the homeConfigurations attribute names is read out of flake.nix by
# ic_flake_user below, so a fork that edits only flake.nix stays consistent. Set
# this only when flake.nix cannot be read at all.

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

# Reads the one-line `dotfilesDir = "${config.home.homeDirectory}<rel>"` literal
# out of an entry module and prints <rel>. Everything the activation wires into
# the machine is built from that literal, so the shell-side guards compare the
# checkout against it before anything is installed.
#
# Parsed with the shell alone rather than sed: the guards run on lean userlands
# where sed may be absent, and a parser that is missing would empty the answer
# and silently disable the guard. Exit codes are distinct so callers can tell
# the tolerated case apart from the one worth reporting:
#   0  literal parsed, printed on stdout
#   1  the file declares no literal in the expected shape (guard skips)
#   2  the file could not be read at all (worth saying so)
ic_declared_dotfiles_rel() {
  local module="$1" line rest
  [ -r "$module" ] || return 2
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'dotfilesDir = "${config.home.homeDirectory}'*'"'*) ;;
      *) continue ;;
    esac
    rest=${line#*'dotfilesDir = "${config.home.homeDirectory}'}
    rest=${rest%%'"'*}
    [ -n "$rest" ] || return 1
    printf '%s\n' "$rest"
    return 0
  done < "$module"
  return 1
}

# The username flake.nix declares. It is the literal that builds the
# homeConfigurations attribute names, so the profile names below are derived
# from it rather than restated here: a fork that replaces it in flake.nix alone
# would otherwise be handed a profile name the flake does not define, and only
# find out inside `nix build` after Nix had already been installed.
# IC_FLAKE_USER overrides, for a caller that cannot point at the flake.
ic_flake_user() {
  local flake="${1:-}/flake.nix" line rest
  if [ -n "${IC_FLAKE_USER:-}" ]; then
    printf '%s\n' "$IC_FLAKE_USER"
    return 0
  fi
  [ -r "$flake" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'username = "'*'"'*) ;;
      *) continue ;;
    esac
    rest=${line#*'username = "'}
    rest=${rest%%'"'*}
    [ -n "$rest" ] || return 1
    printf '%s\n' "$rest"
    return 0
  done < "$flake"
  return 1
}

# Maps a target plus an architecture onto the flake output that installs it.
# macOS has exactly one system configuration; Linux and WSL are per-architecture
# Home Manager profiles, and picking the wrong one would rebuild for the wrong
# CPU, so the architecture is part of the name.
#
# Returns non-zero rather than guessing when the architecture is not one the
# flake has an output for, or when the username cannot be derived. Both would
# otherwise surface much later as an opaque failure inside `nix build`, on a
# machine that already had Nix installed on it.
ic_profile_for() {
  local target="$1" arch="$2" root="${3:-}" user suffix
  case "$target" in
    darwin) echo "darwinConfigurations.mac"; return 0 ;;
    linux|wsl) ;;
    *) return 1 ;;
  esac
  case "$arch" in
    aarch64) suffix="${target}-aarch64" ;;
    x86_64) suffix="$target" ;;
    *) return 1 ;;
  esac
  user=$(ic_flake_user "$root") || return 1
  echo "${user}@${suffix}"
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

# The bin directory of the Node.js version nvm would select, or non-zero when
# nvm is not installed. Nothing under nix/ provides Node on any platform, and
# both setup scripts install it through nvm alone, so on a machine bootstrapped
# from this repo this is the only place node, npm, pnpm and the npm-linked axi
# binaries live; a PATH without it makes the weekly sync-forks run and ic-doctor
# report every one of them missing on a perfectly healthy machine.
#
# Globbing and parameter expansion only, no subprocesses: platform.sh is sourced
# by every interactive zsh.
ic_nvm_bin() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  local versions_dir="$nvm_dir/versions/node"
  [ -d "$versions_dir" ] || return 1

  # zsh aborts the function on a glob that matches nothing, where bash leaves
  # the pattern intact for the -d test below to reject. Localised, so sourcing
  # this file never changes the caller's options.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt local_options no_nomatch
  fi

  # nvm's `default` alias, followed a few hops: the file names either a version
  # outright (v20.11.0) or another alias (`lts/*`, then `lts/iron`), which is
  # itself a file under alias/ holding the next step.
  local name=default target hops=0
  while [ "$hops" -lt 4 ] && [ -f "$nvm_dir/alias/$name" ]; do
    target=""
    read -r target < "$nvm_dir/alias/$name" || true
    [ -n "$target" ] || break
    case "$target" in
      v[0-9]*)
        [ -d "$versions_dir/$target/bin" ] || break
        printf '%s\n' "$versions_dir/$target/bin"
        return 0
        ;;
    esac
    name="$target"
    hops=$((hops + 1))
  done

  # No usable default alias (or a virtual one like `node`): the newest installed
  # version, compared field by field so v9 does not outrank v20.
  local best="" best_major=-1 best_minor=-1 best_patch=-1
  local d version rest major minor patch
  for d in "$versions_dir"/v*; do
    [ -d "$d/bin" ] || continue
    version=${d##*/}
    rest=${version#v}
    major=${rest%%.*}
    rest=${rest#*.}
    minor=${rest%%.*}
    patch=${rest#*.}
    patch=${patch%%[!0-9]*}
    case "$major:$minor:$patch" in
      *[!0-9:]*|*::*) continue ;;
    esac
    if [ "$major" -gt "$best_major" ] ||
       { [ "$major" -eq "$best_major" ] && [ "$minor" -gt "$best_minor" ]; } ||
       { [ "$major" -eq "$best_major" ] && [ "$minor" -eq "$best_minor" ] && [ "$patch" -gt "$best_patch" ]; }; then
      best="$d/bin"
      best_major=$major
      best_minor=$minor
      best_patch=$patch
    fi
  done
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

# A PATH that works under the minimal environment launchd and systemd hand to
# timers, where the user's shell profile has never been sourced.
ic_default_path() {
  local nvm_bin
  nvm_bin=$(ic_nvm_bin) || nvm_bin=""
  if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
    # Behind /opt/homebrew/bin deliberately. A Mac bootstrapped by setup/mac.sh
    # has Node only under ~/.nvm, so without this entry every pnpm arm of the
    # weekly sync-forks run and every Node tool ic-doctor looks for is missing.
    # A machine that also has a hand-installed Homebrew node keeps using it,
    # rather than silently switching Node version at the next timer run.
    echo "$HOME/.local/bin:/opt/homebrew/bin${nvm_bin:+:$nvm_bin}:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$HOME/go/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  else
    # The nvm entry sits where /opt/homebrew/bin sits above: ahead of the system
    # directories, so a distro-packaged node cannot shadow the version nvm
    # selected and the tools npm-linked into it.
    echo "$HOME/.local/bin${nvm_bin:+:$nvm_bin}:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
