{ lib, ... }:

# WSL-only adjustments on top of linux.nix.
#
# WSL2 runs a real Linux kernel, so the Linux profile applies almost unchanged.
# The differences are that systemd is opt-in (and off by default) and that there
# is no display server, so the desktop layer is not composed into this profile
# at all.

{
  # The unit files are still written, but nothing enables them: on a WSL distro
  # without `systemd=true` in /etc/wsl.conf there is no user manager to run the
  # timer, and leaving it wanted would fail activation. Run `syncforks` by hand,
  # or enable systemd in wsl.conf and switch to the linux profile behaviour.
  systemd.user.timers.sync-forks.Install.WantedBy = lib.mkForce [ ];

  # Windows interop: WSL puts the Windows PATH on $PATH, so these resolve to the
  # host's binaries and let the shell reach the Windows side of the machine.
  home.shellAliases = {
    open = "explorer.exe";
    pbcopy = "clip.exe";
  };
}
