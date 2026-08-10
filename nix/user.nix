{ config, ... }:

# macOS Home Manager entry point, composed from the shared layers in ./home.
#
# The dotfilesDir literal below is parsed out of this file by setup/mac.sh,
# files/bin/ic-link, and files/bin/ic-doctor to learn where the checkout must
# live. Keep it on one line and in this shape, or those consumers silently stop
# finding it. The assertion keeps it honest: the home modules derive the same
# path independently from config.home.homeDirectory, and this fails the build if
# the two ever drift apart.

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
      assertion = builtins.elem "${dotfilesDir}/files/bin" config.home.sessionPath;
      message = "nix/user.nix dotfilesDir (${dotfilesDir}) disagrees with the path the home modules derived; the shell-side guards parse the literal in this file, so the two must match.";
    }
  ];
}
