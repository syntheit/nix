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

    windscribe = {
      url = "github:syntheit/windscribe-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    foyer = {
      url = "github:syntheit/foyer";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-avf = {
      url = "github:nix-community/nixos-avf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
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
        mantle = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = specialArgs // {
            hostName = "mantle";
          };
          modules = [
            ./hosts/mantle
            inputs.home-manager.nixosModules.home-manager
            inputs.windscribe.nixosModules.default
            {
              nixpkgs.overlays = [
                inputs.nur.overlays.default
                inputs.windscribe.overlays.default
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              services.windscribe.enable = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "mantle";
              };
              home-manager.users."${vars.user.name}" = import ./home;
            }
          ];
        };

        ledger = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = specialArgs // {
            hostName = "ledger";
          };
          modules = [
            ./hosts/ledger
            inputs.home-manager.nixosModules.home-manager
            inputs.windscribe.nixosModules.default
            {
              nixpkgs.overlays = [
                inputs.nur.overlays.default
                inputs.windscribe.overlays.default
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              services.windscribe.enable = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "ledger";
              };
              home-manager.users."${vars.user.name}" = import ./home;
            }
          ];
        };

        harbor = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = specialArgs // {
            hostName = "harbor";
          };
          modules = [
            ./hosts/harbor
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "harbor";
              };
              home-manager.users."matv" = import ./hosts/harbor/home.nix;
            }
          ];
        };

        conduit = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = specialArgs // {
            hostName = "conduit";
          };
          modules = [
            ./hosts/conduit
            inputs.home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "conduit";
              };
              home-manager.users."matv" = import ./hosts/conduit/home.nix;
            }
          ];
        };

        raven = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = specialArgs // {
            hostName = "raven";
          };
          modules = [
            ./hosts/raven
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "raven";
              };
              home-manager.users."droid" = import ./hosts/raven/home.nix;
            }
          ];
        };
      };

      darwinConfigurations = {
        swift = inputs.nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = specialArgs // {
            hostName = "swift";
          };
          modules = [
            ./hosts/swift
            inputs.sops-nix.darwinModules.sops
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
                hostName = "swift";
              };
              home-manager.users."${vars.user.name}" = import ./hosts/swift/home.nix;
            }
          ];
        };
      };
    };
}
