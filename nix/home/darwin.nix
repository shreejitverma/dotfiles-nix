{ config, ... }:

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

  programs.zsh.shellAliases.rebuild =
    "/run/current-system/sw/bin/darwin-rebuild switch --flake ${dotfilesDir}#mac";

  # Weekly sync of forked tooling (~/github/*) with their upstream parents.
  # Runs Sundays at 10:00. The script merges upstream, pushes your fork, and
  # rebuilds the tools. Logs land in ~/Library/Logs/sync-forks*.log.
  launchd.agents.sync-forks = {
    enable = true;
    config = {
      ProgramArguments = [ "${dotfilesDir}/files/bin/sync-forks" ];
      StartCalendarInterval = [
        { Weekday = 0; Hour = 10; Minute = 0; }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sync-forks.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sync-forks.err.log";
      RunAtLoad = false;
      ProcessType = "Background";
    };
  };
}
