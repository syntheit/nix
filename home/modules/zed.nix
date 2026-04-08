{ pkgs, ... }:

{
  programs.zed-editor = {
    enable = true;

    extensions = [
      "nix"
      "toml"
      "make"
      "docker-compose"
      "dockerfile"
      "csv"
      "git-firefly"
      "sql"
      "helm"
      "tailwind-css"
      "python"
      "basher"
      "prisma"
      "svelte"
    ];

    extraPackages = with pkgs; [
      nil
      nixfmt
      gopls
      pyright
      typescript-language-server
    ];

    userSettings = {
      languages = {
        Nix = {
          language_servers = [ "nil" "!nixd" ];
          formatter = {
            external = {
              command = "nixfmt";
            };
          };
        };
      };

      lsp = {
        nil = {
          settings = {
            formatting = {
              command = [ "nixfmt" ];
            };
            nix = {
              flake = {
                autoArchive = true;
              };
            };
          };
        };
      };
    };
  };
}
