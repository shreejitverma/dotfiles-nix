{ config, profileName, ... }:

# Desktop-Linux Home Manager entry point.
#
# Activated with standalone Home Manager, not nix-darwin, so `rebuild` switches
# the user generation rather than a system one. See nix/home/linux.nix for why.
#
# The dotfilesDir literal below is parsed out of this file by setup/linux.sh,
# exactly as setup/mac.sh parses nix/user.nix. Keep it on one line in this shape.

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles-nix";
in
{
  imports = [
    ./home/common.nix
    ./home/desktop.nix
    ./home/linux.nix
  ];

  programs.zsh.shellAliases.rebuild =
    "home-manager switch --flake ${dotfilesDir}#${profileName}";

  assertions = [
    {
      assertion = builtins.elem "${dotfilesDir}/files/bin" config.home.sessionPath;
      message = "nix/linux-user.nix dotfilesDir (${dotfilesDir}) disagrees with the path the home modules derived; setup/linux.sh parses the literal in this file, so the two must match.";
    }
  ];
}
