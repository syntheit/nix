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
    # The freeform `settings` API uses upstream OpenSSH directive names
    # (HostName, IdentityFile, User, Port, ...) directly. Attribute names are
    # interpreted as `Host` patterns unless prefixed with `Host `/`Match `.
    settings = {
      "*" = {
        IdentityFile = "~/.ssh/mainkey";
        # Reuse connections — eliminates handshake on subsequent sessions
        ControlMaster = "auto";
        ControlPath = "~/.ssh/sockets/%r@%h-%p";
        ControlPersist = "10m";
        # Don't wait for TCP ACK to send data
        TCPKeepAlive = "yes";
        # Detect dead connections faster
        ServerAliveInterval = 15;
        ServerAliveCountMax = 3;
        # Disable compression on fast links (adds latency)
        Compression = "no";
      };
      "harbor" = {
        HostName = "100.109.63.87";
        IdentityFile = "~/.ssh/mainkey";
        User = "matv";
        Port = 64829;
      };
      "harbor.tunnel" = {
        HostName = "harbor-ssh.matv.io";
        IdentityFile = "~/.ssh/mainkey";
        User = "matv";
        Port = 64829;
        ProxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
      };
      "swift" = {
        HostName = "100.78.114.100";
        IdentityFile = "~/.ssh/mainkey";
        User = "daniel";
      };
      "mantle" = {
        HostName = "100.75.104.50";
        IdentityFile = "~/.ssh/mainkey";
        User = "daniel";
      };
      "vista" = {
        HostName = "100.96.21.56";
        IdentityFile = "~/.ssh/mainkey";
        User = "daniel";
      };
      "raven" = {
        HostName = "100.98.64.97";
        IdentityFile = "~/.ssh/mainkey";
        User = "droid";
      };
      "raven.tunnel" = {
        HostName = "raven-ssh.matv.io";
        IdentityFile = "~/.ssh/mainkey";
        User = "droid";
        ProxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
      };
      "conduit" = {
        HostName = "192.3.203.146";
        IdentityFile = "~/.ssh/mainkey";
        User = "matv";
        Port = 64829;
      };
      # Lab VMs on harbor — proxy through harbor since they're on virbr0 NAT
      "turntable" = {
        HostName = "192.168.122.50";
        IdentityFile = "~/.ssh/mainkey";
        User = "root";
        ProxyJump = "harbor";
      };
      # Direct connection — runs from harbor (which is on the same virbr0 network).
      # From swift, use: ssh -J harbor user@192.168.122.200
      "haiku" = {
        HostName = "192.168.122.200";
        IdentityFile = "~/.ssh/mainkey";
        User = "user";
      };
      "gandalf" = {
        HostName = "100.64.0.2";
        IdentityFile = "~/.ssh/conduit_key";
        IdentitiesOnly = true;
        User = "tars";
      };
      "github.com" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/mainkey";
      };
      # Alias matching the deploy-key-pinned alias used inside the
      # headscale container. Points at the same github.com host with
      # daniel's mainkey so flake updates work from harbor too.
      "github-malli-deus" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/mainkey";
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
