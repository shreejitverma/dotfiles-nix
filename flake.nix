{
  description = "Minimal cross-platform Nix setup: nix-darwin + Home Manager on macOS, standalone Home Manager on Linux and WSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix-darwin, home-manager, ... }:
    let
      username = "shreejitverma";

      # Standalone Home Manager profiles for Linux and WSL. macOS is not here:
      # nix-darwin owns the whole machine there and activates Home Manager as a
      # module, which is why it is a darwinConfiguration below instead.
      #
      # profileName is threaded back into each configuration so its `rebuild`
      # alias names the profile it was actually built from, which is what makes
      # the aarch64 variants correct rather than silently rebuilding x86_64.
      mkHome = { system, module, profileName }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          extraSpecialArgs = { inherit profileName; };
          modules = [ module ];
        };

      linuxProfiles = [
        { suffix = "linux"; system = "x86_64-linux"; module = ./nix/linux-user.nix; }
        { suffix = "linux-aarch64"; system = "aarch64-linux"; module = ./nix/linux-user.nix; }
        { suffix = "wsl"; system = "x86_64-linux"; module = ./nix/wsl-user.nix; }
        { suffix = "wsl-aarch64"; system = "aarch64-linux"; module = ./nix/wsl-user.nix; }
      ];
    in
    {
      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./nix/host.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.shreejitverma = import ./nix/user.nix;
          }
        ];
      };

      homeConfigurations = builtins.listToAttrs (map
        (p: {
          name = "${username}@${p.suffix}";
          value = mkHome {
            inherit (p) system module;
            profileName = "${username}@${p.suffix}";
          };
        })
        linuxProfiles);
    };
}
