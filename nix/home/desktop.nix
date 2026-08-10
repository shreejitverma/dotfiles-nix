{ config, pkgs, ... }:

# The GUI-facing layer: fonts and the app configs linked out of the repo.
#
# Composed into the macOS and desktop-Linux profiles, and deliberately left out
# of the WSL profile, which has no display server and no use for either.

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles-nix";
in
{
  home.packages = with pkgs; [
    nerd-fonts.hack
    roboto
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    font-awesome
  ];

  fonts.fontconfig.enable = true;

  home.file = {
    ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/wezterm";
    # ~/.config/nvim is deliberately NOT managed here: it is its own git repo
    # (github.com/shreejitverma/kickstart.nvim) checked out in place.
    ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/herdr";
  };
}
