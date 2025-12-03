{ pkgs, inputs, ... }:

let
  cli-tools = import ./cli-tools.nix { inherit pkgs; };
  media = import ./media.nix { inherit pkgs; };
  development = import ./development.nix { inherit pkgs; };
  graphics = import ./graphics.nix { inherit pkgs; };
  hyprland = import ./hyprland.nix { inherit pkgs; };
  system = import ./system.nix { inherit pkgs inputs; };
in
{
  home.packages = cli-tools ++ media ++ development ++ graphics ++ hyprland ++ system;
}
