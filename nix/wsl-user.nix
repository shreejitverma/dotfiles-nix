{ config, profileName, ... }:

# WSL Home Manager entry point.
#
# Same shape as linux-user.nix, minus the desktop layer: a WSL distro has no
# display server, so fonts and the linked terminal configs would be dead weight.
#
# The dotfilesDir literal below is parsed out of this file by setup/linux.sh,
# exactly as setup/mac.sh parses nix/user.nix. Keep it on one line in this shape.

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles-nix";
in
{
  imports = [
    ./home/common.nix
    ./home/linux.nix
    ./home/wsl.nix
  ];

  programs.zsh.shellAliases.rebuild =
    "home-manager switch --flake ${dotfilesDir}#${profileName}";

  assertions = [
    {
      assertion = builtins.elem "${dotfilesDir}/files/bin" config.home.sessionPath;
      message = "nix/wsl-user.nix dotfilesDir (${dotfilesDir}) disagrees with the path the home modules derived; setup/linux.sh parses the literal in this file, so the two must match.";
    }
  ];
}
