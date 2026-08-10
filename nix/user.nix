{ config, ... }:

# macOS Home Manager entry point, composed from the shared layers in ./home.
#
# The dotfilesDir literal below is parsed out of this file by setup/mac.sh,
# files/bin/ic-link, and files/bin/ic-doctor to learn where the checkout must
# live. Keep it on one line and in this shape, or those consumers silently stop
# finding it. The assertion keeps it honest: nix/home/dotfiles.nix holds the one
# definition every layer derives its paths from, and this fails the build if the
# literal here and that definition ever drift apart.

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles-nix";
in
{
  imports = [
    ./home/common.nix
    ./home/desktop.nix
    ./home/darwin.nix
  ];

  assertions = [
    {
      assertion = dotfilesDir == config.ic.dotfilesDir;
      message = "nix/user.nix dotfilesDir (${dotfilesDir}) disagrees with nix/home/dotfiles.nix (${config.ic.dotfilesDir}), which every layer derives its links, PATH entry, and agent from; the shell-side guards parse the literal in this file, so the two must match.";
    }
  ];
}
