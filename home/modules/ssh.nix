{ pkgs, ... }:

{
  home.packages = [
    pkgs.cloudflared
  ];

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "admin.matv.io" = {
        hostname = "admin.matv.io";
        identityFile = "~/.ssh/mainkey"; # Points to the manual file
        port = 64829;
        # We use strict interpolation to point to the exact binary
        proxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
      };
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/mainkey";
      };
    };
  };
}

