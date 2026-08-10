{ config, lib, ... }:

# The one definition of where this checkout lives, read by every layer.
#
# Everything the activation wires into the machine is derived from this path:
# the files/bin PATH entry, the zsh workflow layer, the out-of-store app config
# symlinks, and the sync-forks agent or timer. Before this module existed the
# same let-binding was repeated in each layer, so one layer could be edited on
# its own and silently repoint just the paths it derived, with no assertion to
# catch the drift. readOnly makes a second definition a build error rather than
# a divergence.
#
# Derived from home.homeDirectory rather than hardcoded, so the same expression
# resolves to /Users/<user>/... on macOS and /home/<user>/... on Linux and WSL.
#
# The three entry modules still spell the path out in a one-line literal,
# because setup/mac.sh, setup/linux.sh, files/bin/ic-link and files/bin/ic-doctor
# parse it textually; each asserts its literal against this value.

{
  options.ic.dotfilesDir = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "${config.home.homeDirectory}/github/dotfiles-nix";
    defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/github/dotfiles-nix"'';
    description = "Absolute path of this dotfiles checkout, which every layer links and sources out of.";
  };
}
