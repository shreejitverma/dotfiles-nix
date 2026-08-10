{ config, ... }:

# Shared Linux and WSL Home Manager layer.
#
# Unlike macOS, this repo does not own the machine here: nix-darwin has no Linux
# equivalent for an existing distro, so these profiles are activated with
# standalone Home Manager and manage the user environment only. The kernel,
# services, display server, and distro packages stay with the distro.
#
# The weekly fork sync is a systemd user timer here, mirroring the launchd agent
# in darwin.nix. WSL disables the timer in wsl.nix, because systemd is opt-in
# there and off by default.

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles-nix";
in
{
  home.homeDirectory = "/home/shreejitverma";

  # Installs the `home-manager` CLI into the profile. macOS does not need this
  # (nix-darwin drives activation there), but on Linux and WSL it is what the
  # `rebuild` alias invokes, so without it the alias breaks after first install.
  programs.home-manager.enable = true;

  systemd.user.services.sync-forks = {
    Unit.Description = "Sync forked tooling in ~/github with their upstream parents";
    Service = {
      Type = "oneshot";
      ExecStart = "${dotfilesDir}/files/bin/sync-forks";
    };
  };

  systemd.user.timers.sync-forks = {
    Unit.Description = "Weekly fork sync (Sundays 10:00)";
    Timer = {
      OnCalendar = "Sun *-*-* 10:00:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
