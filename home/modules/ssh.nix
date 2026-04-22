{
  pkgs,
  lib,
  config,
  ...
}:

{
  home.file.".ssh/config".force = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        identityFile = "~/.ssh/mainkey";
        extraOptions = {
          # Reuse connections — eliminates handshake on subsequent sessions
          ControlMaster = "auto";
          ControlPath = "~/.ssh/sockets/%r@%h-%p";
          ControlPersist = "10m";
          # Don't wait for TCP ACK to send data
          TCPKeepAlive = "yes";
          # Detect dead connections faster
          ServerAliveInterval = "15";
          ServerAliveCountMax = "3";
          # Disable compression on fast links (adds latency)
          Compression = "no";
        };
      };
      "harbor" = {
        hostname = "100.109.63.87";
        identityFile = "~/.ssh/mainkey";
        user = "matv";
        port = 64829;
      };
      "harbor.tunnel" = {
        hostname = "harbor-ssh.matv.io";
        identityFile = "~/.ssh/mainkey";
        user = "matv";
        port = 64829;
        proxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
      };
      "swift" = {
        hostname = "100.78.114.100";
        identityFile = "~/.ssh/mainkey";
        user = "daniel";
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
      "gandalf" = {
        hostname = "100.64.0.2";
        identityFile = "~/.ssh/conduit_key";
        identitiesOnly = true;
        user = "tars";
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
    $DRY_RUN_CMD mkdir -p "$HOME/.ssh/sockets"
    SSH_CONFIG="$HOME/.ssh/config"
    if [ -L "$SSH_CONFIG" ]; then
      SRC=$(readlink -f "$SSH_CONFIG")
      $DRY_RUN_CMD rm -f "$SSH_CONFIG"
      $DRY_RUN_CMD cp "$SRC" "$SSH_CONFIG"
      $DRY_RUN_CMD chmod 600 "$SSH_CONFIG"
    fi
  '';
}
