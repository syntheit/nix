{
  description = "NixOS Config Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nixpkgs-unstable pinned to 2026-07-05: the 2026-07-13 channel bump
    # switched the darwin toolchain to ld64 957.1 / SDK 26.5, whose ld
    # dies with SIGTRAP linking real framework symbols on macOS 26.3
    # (first casualty: blueutil), and Hydra has no cached binaries for it
    # yet. Unpin back to nixpkgs-unstable once the toolchain builds clean.
    nixpkgs-darwin.url = "github:nixos/nixpkgs/f205b5574fd0cb7da5b702a2da51507b7f4fdd1b";

    # GNOME 49 pin for fajita's GNOME Shell Mobile session. verdre's
    # gnome-shell-mobile / mutter-mobile top out at the GNOME 49
    # (mobile-shell-devel-49) branch, so the mobile overlay
    # (packages/gnome-mobile) must be applied on a GNOME-49 base. This is
    # nixos-unstable @ 2026-05-05 — the last channel commit before GNOME 50
    # landed (gnome-shell 49.4). Bump in lockstep with the overlay's pins when
    # verdre moves to GNOME 50.
    nixpkgs-gnome49.url = "github:nixos/nixpkgs/bb39d8133e1b525230b72ec50862b193882cc910";

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
      inputs.nixpkgs.follows = "nixpkgs-darwin";
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

    elliot = {
      url = "github:syntheit/elliot";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jelly-recs = {
      url = "github:syntheit/jelly-recs";
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

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Mobile NixOS — fajita (OnePlus 6T). mwlaboratories fork carries the SDM845
    # kernel 6.19 bump + depmod cross-compile fix; upstream is pinned to 6.4 and
    # stale. Imported as plain source (not a flake).
    mobile-nixos = {
      url = "github:mwlaboratories/mobile-nixos/sdm845-bleeding-edge";
      flake = false;
    };

    # Marble GNOME Shell theme — our fork adds GNOME 49/50 support + the
    # --gnome-version flag (needed to build the theme in a sandbox). Plain
    # Python source (not a flake); built by packages/marble-shell-theme and
    # wired up in hosts/fajita/theme.nix.
    marble-shell-theme = {
      url = "github:syntheit/Marble-shell-theme/gnome-49-50-support";
      flake = false;
    };

    malli-nix = {
      url = "git+ssh://git@github.com/NRE-Product/malli-nix.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deus = {
      # git+ssh via the github-malli-deus alias defined in
      # home/modules/ssh.nix → github.com + ~/.ssh/mainkey, which has
      # a deploy key on the malli-deus repo. SSH keys don't expire,
      # unlike PATs — the previous git+https + /etc/nix/netrc path
      # silently broke whenever the GitHub PAT rotated out.
      url = "git+ssh://git@github-malli-deus/NRE-Product/malli-deus.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vestal = {
      url = "github:syntheit/vestal";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # Anchorage — native GTK4/libadwaita Linkding client (Linkding bookmarks).
    anchorage = {
      url = "git+ssh://git@github.com/syntheit/anchorage.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Jotter — native GTK4/libadwaita Memos client (notes.matv.io).
    jotter = {
      url = "git+ssh://git@github.com/syntheit/jotter.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Warden — native GTK4/libadwaita Bitwarden/Vaultwarden client (over rbw).
    warden = {
      url = "git+ssh://git@github.com/syntheit/warden.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Courier — native GTK4/libadwaita mobile email client (IMAP/SMTP, offline SQLite, privacy-first HTML).
    # Pinned to a committed rev because the local worktree carries WIP; drop ?rev= to track HEAD once clean.
    courier = {
      url = "git+file:///home/matv/Projects/courier?rev=2587fac0bd646a6622efc66185cbcb1ab3a2a7cd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Calculator — native GTK4/libadwaita Google-Calculator-style app (mobile-first).
    calculator = {
      url = "git+file:///home/matv/Projects/calculator?rev=58d6fb640f10327912086bc5df4f8c03883eff4c";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Bourse — native GTK4/libadwaita stocks watchlist app (Yahoo Finance, no API key).
    bourse = {
      url = "git+file:///home/matv/Projects/bourse?rev=cb6fb484de2ccee653076e137101d780575a0a95";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Paloma — native GTK4/libadwaita Telegram client (over TDLib). api_id/api_hash
    # are injected at RUNTIME from sops, not baked at build time (see
    # overlays/default.nix paloma-wrapped + hosts' secrets).
    paloma = {
      url = "git+ssh://git@github.com/syntheit/paloma.git";
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
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            inputs.windscribe.nixosModules.default
            {
              nixpkgs.overlays = [
                inputs.nur.overlays.default
                inputs.windscribe.overlays.default
                inputs.affinity-nix.overlays.default
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
                inputs.affinity-nix.overlays.default
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

        # fajita — OnePlus 6T running Mobile NixOS + GNOME Shell Mobile. Built on
        # harbor via aarch64-linux binfmt emulation; flashed to phone over
        # fastboot. Pinned to nixpkgs-gnome49 (GNOME 49.4) to match verdre's
        # mobile-shell-devel-49 overlay (packages/gnome-mobile).
        fajita = inputs.nixpkgs-gnome49.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = specialArgs // {
            hostName = "fajita";
          };
          modules = [
            (import "${inputs.mobile-nixos}/lib/configuration.nix" { device = "oneplus-fajita"; })
            ./hosts/fajita
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            {
              # Windscribe doesn't ship aarch64 builds — skip on fajita; on the
              # phone use NetworkManager VPN profiles directly if needed.
              nixpkgs.overlays = [
                (import ./overlays { inherit inputs lib; }).modifications
                (import ./overlays { inherit inputs lib; }).additions
              ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bkp";
              home-manager.extraSpecialArgs = specialArgs // {
                hostName = "fajita";
              };
              home-manager.users."daniel" = import ./hosts/fajita/home.nix;
            }
          ];
        };

        # vista — 2019 16" MacBook Pro (MacBookPro16,1, Apple T2) repurposed as
        # an always-on headless server (lid shut, no GUI, ethernet, SSH-managed).
        vista = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = specialArgs // {
            hostName = "vista";
          };
          modules = [
            ./hosts/vista
            inputs.nixos-hardware.nixosModules.apple-t2
            inputs.disko.nixosModules.disko
            inputs.sops-nix.nixosModules.sops
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
                hostName = "vista";
              };
              # Slim headless-server home profile — NOT the full ./home kitchen sink.
              home-manager.users."${vars.user.name}" = import ./hosts/vista/home.nix;
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

        mini = inputs.nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = specialArgs // {
            hostName = "mini";
          };
          modules = [
            ./hosts/mini
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
                hostName = "mini";
              };
              home-manager.users."${vars.user.name}" = import ./hosts/mini/home.nix;
            }
          ];
        };
      };
    };
}
