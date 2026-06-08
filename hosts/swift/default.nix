{
  pkgs,
  ...
}:

let
  tccGrants = import ./tcc-grants.nix { inherit pkgs; };
in
{
  imports = [
    ../../modules/darwin/common.nix
    ./homebrew.nix
    # ./sharp-corners.nix  # temporarily disabled — breaks hardened apps (Ghostty)
  ];

  networking.hostName = "swift";

  matv.darwin.tccGrants = tccGrants;

  # MacBook with TouchID — sudo via fingerprint, reattach across sudo-relogin
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;

  services.skhd = {
    enable = true;
    package = pkgs.skhd;
    skhdConfig = builtins.readFile ./skhdrc;
  };
}
