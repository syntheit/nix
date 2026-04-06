{
  description = "NixOS Config Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    antigravity = {
      url = "github:jacopone/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland from nixpkgs is used instead (more stable builds)
    # hyprland = {
    #   url = "git+https://github.com/hyprwm/Hyprland?submodules=1&ref=refs/tags/v0.53.3";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    affinity-nix = {
      url = "github:mrshmllow/affinity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      affinity-nix,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      vars = import ./vars;
      specialArgs = {
        inherit inputs;
        inherit vars;
        extraLibs = import ./libs { inherit lib; };
      };
    in
    {
      nixosConfigurations = {
        caspian = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = specialArgs // {
            hostName = "caspian";
          };
          modules = [
            ./hosts/caspian
            inputs.home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [
                inputs.nur.overlays.default
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "caspian";
              };
              home-manager.users."${vars.user.name}" = import ./home;
            }
          ];
        };

        ionian = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = specialArgs // {
            hostName = "ionian";
          };
          modules = [
            ./hosts/ionian
            inputs.home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [
                inputs.nur.overlays.default
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "ionian";
              };
              home-manager.users."${vars.user.name}" = import ./home;
            }
          ];
        };
      };

      darwinConfigurations = {
        aegean = inputs.nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = specialArgs // {
            hostName = "aegean";
          };
          modules = [
            ./hosts/aegean
            inputs.nix-homebrew.darwinModules.nix-homebrew
            inputs.home-manager.darwinModules.home-manager
            {
              nixpkgs.overlays = [
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "aegean";
              };
              home-manager.users."${vars.user.name}" = import ./hosts/aegean/home.nix;
            }
          ];
        };
      };
    };
}
