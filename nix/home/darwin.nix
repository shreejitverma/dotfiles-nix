{ config, lib, ... }:

# macOS-only Home Manager layer: the launchd agent, the macOS home directory,
# and the `rebuild` alias that drives nix-darwin.
#
# On macOS this repo owns the whole machine through nix-darwin, so `rebuild`
# activates a system generation. The Linux and WSL profiles have no equivalent
# and activate only the user environment; see linux.nix.

let
  dotfilesDir = config.ic.dotfilesDir;
in
{
  imports = [ ./dotfiles.nix ];

  home.homeDirectory = "/Users/shreejitverma";

  # The flake reference is single-quoted inside the alias body on purpose.
  # files/zsh/ic-workflow.zsh sets EXTENDED_GLOB, which makes `#` a repetition
  # operator, so an unquoted <path>#mac is read as the pattern `ni` + `x#` +
  # `mac`; it matches nothing and the alias dies with "no matches found" before
  # darwin-rebuild is ever reached. Alias expansion is textual, so the quotes
  # have to survive into the expanded command line.
  programs.zsh.shellAliases.rebuild =
    "/run/current-system/sw/bin/darwin-rebuild switch --flake '${dotfilesDir}#mac'";

  # Enforce signing only here: the signing key (~/.ssh/id_ed25519_signing,
  # generated manually on this Mac and registered on GitHub) is machine-local,
  # so Linux/WSL activations inherit the format and key from common.nix but
  # never force signing with a key that does not exist there.
  programs.git.signing.signByDefault = true;

  # Daily sync of forked tooling (~/github/*) with their upstream parents,
  # driven by the fleet manifest (~/github/.fleet/manifest.yaml). Runs daily
  # at 10:00; RunAtLoad picks up a run missed while the laptop was asleep or
  # off. The script fast-forwards from upstream (never merges), pushes the
  # fork, re-asserts commit identity, and reinstalls updated tools. Detailed
  # logs land in ~/github/.fleet/logs/sync-YYYYMMDD.log (30-day rotation);
  # the paths below only catch launchd-level stdout/stderr.
  #
  # launchd does not create intermediate directories for StandardOutPath /
  # StandardErrorPath, and RunAtLoad fires at activation - before the external
  # fleet bootstrap has ever run on a fresh machine. The activation step below
  # guarantees the directory exists so the agent can always spawn and reach the
  # script's graceful no-manifest exit.
  home.activation.fleetLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${config.home.homeDirectory}/github/.fleet/logs"
  '';

  launchd.agents.sync-forks = {
    enable = true;
    config = {
      ProgramArguments = [ "${dotfilesDir}/files/bin/sync-forks" ];
      StartCalendarInterval = [
        { Hour = 10; Minute = 0; }
      ];
      StandardOutPath = "${config.home.homeDirectory}/github/.fleet/logs/launchd.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/github/.fleet/logs/launchd.err.log";
      RunAtLoad = true;
      ProcessType = "Background";
    };
  };
}
