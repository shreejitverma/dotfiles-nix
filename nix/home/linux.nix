{ config, ... }:

# Shared Linux and WSL Home Manager layer.
#
# Unlike macOS, this repo does not own the machine here: nix-darwin has no Linux
# equivalent for an existing distro, so these profiles are activated with
# standalone Home Manager and manage the user environment only. The kernel,
# services, display server, and distro packages stay with the distro.
#
# The daily fork sync is a systemd user timer here, mirroring the launchd agent
# in darwin.nix. WSL disables the timer in wsl.nix, because systemd is opt-in
# there and off by default. On a host without ~/github/.fleet/manifest.yaml the
# script logs that there is nothing to sync and exits 0, so the timer is
# harmless where the fleet is not set up.

let
  dotfilesDir = config.ic.dotfilesDir;
in
{
  imports = [ ./dotfiles.nix ];

  home.homeDirectory = "/home/shreejitverma";

  # Installs the `home-manager` CLI into the profile. macOS does not need this
  # (nix-darwin drives activation there), but on Linux and WSL it is what the
  # `rebuild` alias invokes, so without it the alias breaks after first install.
  programs.home-manager.enable = true;

  # The stock login shell on Debian, Ubuntu and every WSL distro is bash, not
  # zsh. Home Manager only writes hm-session-vars.sh into the shells it manages,
  # so without this the session PATH (including files/bin), the environment and
  # the aliases would exist solely in the generated .zshrc and a normal login
  # would see none of them. Deliberately not in common.nix: macOS already logs
  # in with zsh, and enabling bash there would generate .bashrc/.profile that
  # nothing on that machine reads.
  #
  # The aliases are taken from the zsh set rather than restated, so the two can
  # never drift and the platform-specific `rebuild` alias is inherited too. The
  # zsh workflow layer in files/zsh is zsh-only by design and is not sourced
  # here; setup/linux.sh prints how to switch the login shell to zsh.
  programs.bash = {
    enable = true;
    shellAliases = config.programs.zsh.shellAliases;
  };

  systemd.user.services.sync-forks = {
    Unit.Description = "Sync forked tooling in ~/github with their upstream parents";
    Service = {
      Type = "oneshot";
      ExecStart = "${dotfilesDir}/files/bin/sync-forks";
    };
  };

  systemd.user.timers.sync-forks = {
    Unit.Description = "Daily fork sync (10:00)";
    Timer = {
      OnCalendar = "*-*-* 10:00:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
