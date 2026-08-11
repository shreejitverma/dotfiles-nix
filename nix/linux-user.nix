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

  # Quoted for the same reason as the macOS alias in nix/home/darwin.nix:
  # ic-workflow.zsh sets EXTENDED_GLOB, so an unquoted `#` in the flake
  # reference is a glob operator and the alias fails before home-manager runs.
  programs.zsh.shellAliases.rebuild =
    "home-manager switch --flake '${dotfilesDir}#${profileName}'";

  assertions = [
    {
      assertion = dotfilesDir == config.ic.dotfilesDir;
      message = "nix/linux-user.nix dotfilesDir (${dotfilesDir}) disagrees with nix/home/dotfiles.nix (${config.ic.dotfilesDir}), which every layer derives its links, PATH entry, and timer from; setup/linux.sh parses the literal in this file, so the two must match.";
    }
    {
      assertion = builtins.elem "${dotfilesDir}/files/bin" config.home.sessionPath;
      message = "home.sessionPath has no ${dotfilesDir}/files/bin entry, so this activation would leave every script in files/bin off PATH; nix/home/common.nix is where that entry is declared.";
    }
  ];
}
