{ config, ... }:

# macOS Home Manager entry point, composed from the shared layers in ./home.
#
# The dotfilesDir literal below is parsed out of this file by setup/mac.sh,
# files/bin/ic-link, and files/bin/ic-doctor to learn where the checkout must
# live. Keep it on one line and in this shape, or those consumers silently stop
# finding it. The assertions keep it honest: nix/home/dotfiles.nix holds the one
# definition every layer derives its paths from, and the build fails if the
# literal here and that definition ever drift apart, or if the files/bin entry
# that definition feeds ever stops reaching home.sessionPath.

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
    {
      assertion = builtins.elem "${dotfilesDir}/files/bin" config.home.sessionPath;
      message = "home.sessionPath has no ${dotfilesDir}/files/bin entry, so this activation would leave every script in files/bin off PATH; nix/home/common.nix is where that entry is declared.";
    }
  ];
}
