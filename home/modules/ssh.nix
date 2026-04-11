{
  pkgs,
  lib,
  config,
  ...
}:

{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        identityFile = "~/.ssh/mainkey";
      };
      "harbor" = {
        hostname = "100.109.63.87";
        identityFile = "~/.ssh/mainkey";
        user = "matv";
        port = 64829;
      };
      "harbor.tunnel" = {
        hostname = "harbor.matv.io";
        identityFile = "~/.ssh/mainkey";
        user = "matv";
        port = 64829;
        proxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
      };
      "raven" = {
        hostname = "100.98.64.97";
        identityFile = "~/.ssh/mainkey";
        user = "droid";
      };
      "raven.tunnel" = {
        hostname = "raven.matv.io";
        identityFile = "~/.ssh/mainkey";
        user = "droid";
        proxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
      };
      "conduit" = {
        hostname = "192.3.203.146";
        identityFile = "~/.ssh/mainkey";
        user = "matv";
        port = 64829;
      };
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/mainkey";
      };
    };
  };

  # SSH refuses to read a config file that is a symlink to a file owned by someone else.
  # In some Nix environments (like this one), the nix store is owned by 'nobody',
  # which makes SSH complain. This activation script replaces the symlink with a real copy.
  home.activation.fixSshConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SSH_CONFIG="$HOME/.ssh/config"
    if [ -L "$SSH_CONFIG" ]; then
      SRC=$(readlink -f "$SSH_CONFIG")
      $DRY_RUN_CMD rm -f "$SSH_CONFIG"
      $DRY_RUN_CMD cp "$SRC" "$SSH_CONFIG"
      $DRY_RUN_CMD chmod 600 "$SSH_CONFIG"
    fi
  '';
}
