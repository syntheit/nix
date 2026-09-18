{
  lib,
  pkgs,
  vars,
  extraLibs,
  inputs,
  hostName,
  ...
}:
let
  usbToggle = pkgs.writeShellScriptBin "usb-toggle" ''
    # Usage: usb-toggle <device> <action>
    # Devices: mic (Blue Snowball), cam (eMeet C960)
    # Actions: waybar, toggle
    case "$1" in
      mic) VENDOR="0d8c"; PRODUCT="0005"; ON_ICON="󰍬"; OFF_ICON="󰍭"; LABEL="Blue Snowball" ;;
      cam) VENDOR="328f"; PRODUCT="2013"; ON_ICON="󰄀"; OFF_ICON="󰄁"; LABEL="eMeet C960" ;;
      *) echo '{"text":"","tooltip":""}'; exit 1 ;;
    esac

    find_device() {
      for dev in /sys/bus/usb/devices/*/; do
        if [ -f "$dev/idVendor" ] && [ "$(cat "$dev/idVendor" 2>/dev/null)" = "$VENDOR" ] && \
           [ "$(cat "$dev/idProduct" 2>/dev/null)" = "$PRODUCT" ]; then
          echo "$dev"
          return 0
        fi
      done
      return 1
    }

    case "''${2:-waybar}" in
      waybar)
        dev=$(find_device)
        if [ -n "$dev" ]; then
          auth=$(cat "$dev/authorized" 2>/dev/null)
          if [ "$auth" = "1" ]; then
            echo "{\"text\":\"$ON_ICON\",\"tooltip\":\"$LABEL: ON\",\"class\":\"on\"}"
          else
            echo "{\"text\":\"$OFF_ICON\",\"tooltip\":\"$LABEL: OFF\",\"class\":\"off\"}"
          fi
        else
          echo '{"text":"","tooltip":""}'
        fi
        ;;
      toggle)
        dev=$(find_device)
        if [ -n "$dev" ]; then
          auth=$(cat "$dev/authorized" 2>/dev/null)
          if [ "$auth" = "1" ]; then
            echo 0 > "$dev/authorized"
          else
            echo 1 > "$dev/authorized"
          fi
        fi
        ;;
    esac
  '';
  # RAW photo thumbnails for Nautilus. Replaces nufraw-thumbnailer (dropped from
  # nixpkgs 2026-08 for depending on the deprecated GTK2 engine). Every DSLR RAW
  # embeds a JPEG preview; we extract the largest with exiftool and resize with
  # ImageMagick — no slow full RAW decode. Ships a freedesktop .thumbnailer that
  # Nautilus discovers via the `share/thumbnailers` pathsToLink below.
  rawThumbnailerBin = pkgs.writeShellApplication {
    name = "raw-thumbnailer";
    runtimeInputs = [
      pkgs.exiftool
      pkgs.imagemagick
    ];
    text = ''
      size="$1"
      input="$2"
      output="$3"

      tmp="$(mktemp --suffix=.jpg)"
      trap 'rm -f "$tmp"' EXIT

      # Pull the embedded preview, trying tags in descending quality order.
      for tag in JpgFromRaw PreviewImage OtherImage ThumbnailImage; do
        if exiftool -b -"$tag" "$input" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
          break
        fi
      done

      [ -s "$tmp" ] || exit 1

      # Honour embedded orientation, shrink to the requested box, drop metadata.
      exec magick "$tmp" -auto-orient -thumbnail "''${size}x''${size}>" -strip "png:$output"
    '';
  };
  rawThumbnailer = pkgs.writeTextDir "share/thumbnailers/raw.thumbnailer" ''
    [Thumbnailer Entry]
    TryExec=${rawThumbnailerBin}/bin/raw-thumbnailer
    Exec=${rawThumbnailerBin}/bin/raw-thumbnailer %s %i %o
    MimeType=image/x-canon-cr2;image/x-canon-cr3;image/x-canon-crw;image/x-nikon-nef;image/x-nikon-nrw;image/x-sony-arw;image/x-sony-sr2;image/x-sony-srf;image/x-adobe-dng;image/x-fuji-raf;image/x-panasonic-rw2;image/x-panasonic-raw;image/x-olympus-orf;image/x-pentax-pef;image/x-samsung-srw;image/x-kodak-dcr;image/x-minolta-mrw;image/x-sigma-x3f;
  '';
  # GParted wrapper: pkexec strips DISPLAY on Wayland, so we re-inject it via a root helper
  gpartedRoot = pkgs.writeShellScript "gparted-root" ''
    export DISPLAY=''${DISPLAY:-:0}
    exec ${pkgs.gparted}/bin/.gparted-wrapped "$@"
  '';
  gpartedWayland = pkgs.stdenv.mkDerivation {
    name = "gparted-wayland";
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin $out/share/applications
      cat > $out/bin/gparted <<'WRAPPER'
#!/bin/sh
${pkgs.xhost}/bin/xhost +SI:localuser:root >/dev/null 2>&1
pkexec --disable-internal-agent ${gpartedRoot} "$@"
status=$?
${pkgs.xhost}/bin/xhost -SI:localuser:root >/dev/null 2>&1
exit $status
WRAPPER
      chmod +x $out/bin/gparted
      cp -r ${pkgs.gparted}/share/icons $out/share/
      cat > $out/share/applications/gparted.desktop <<DESKTOP
[Desktop Entry]
Name=GParted
Comment=GNOME Partition Editor
Exec=$out/bin/gparted
Icon=gparted
Terminal=false
Type=Application
Categories=GNOME;System;
DESKTOP
    '';
  };
in
{
  imports = extraLibs.scanPaths ./.;

  networking = {
    networkmanager = {
      enable = true;
      # Ensure NetworkManager uses the secret service for storing WiFi passwords
      # This requires libsecret which is provided by gnome-keyring
      # NetworkManager will automatically use the secret service when available
    };
  };

  systemd.services.NetworkManager-wait-online.enable = false;

  # NextDNS via systemd-resolved
  # Configure NetworkManager to use systemd-resolved for DNS
  networking.networkmanager.dns = "systemd-resolved";
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSSEC = "false";
        Domains = [ "~." ];
        FallbackDNS = [ ];
        DNSOverTLS = "true";
      };
    };
  };
  # Configure NextDNS servers via systemd-resolved
  # These will be used by systemd-resolved
  networking.nameservers = [
    "45.90.28.0#57bc2c.dns.nextdns.io"
    "2a07:a8c0::#57bc2c.dns.nextdns.io"
    "45.90.30.0#57bc2c.dns.nextdns.io"
    "2a07:a8c1::#57bc2c.dns.nextdns.io"
  ];

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];
    settings.auto-optimise-store = true;
    settings.max-jobs = "auto";
    settings.cores = 0;
    settings.download-buffer-size = 134217728;
    settings.min-free = 1073741824; # 1GB — auto-GC when free space drops below
    settings.max-free = 3221225472; # 3GB — stop GC once this much space is free
    # Nix garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs = {
    # hostPlatform is set per-host in hardware-configuration.nix
    config.allowUnfree = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    git
    lm_sensors
    iw
    libsecret # Required for NetworkManager to use secret service (gnome-keyring)
    # Thumbnailer packages for file manager previews
    gdk-pixbuf # Basic image formats (PNG, JPEG, BMP, GIF, TIFF, etc.)
    libheif # HEIF and AVIF image formats
    libheif.out # HEIF output plugin
    rawThumbnailer # RAW image thumbnailer (replaces removed nufraw-thumbnailer)
    ffmpegthumbnailer # Video thumbnail generation
    poppler-utils # PDF thumbnail generation
    android-tools
    gpartedWayland # GParted with Wayland DISPLAY fix (replaces xhost + gparted)
    ntfs3g # NTFS read/write support and utilities
    cifs-utils # Samba/Windows network shares
    nfs-utils # NFS network shares
    hfsprogs # HFS+ support
    apfs-fuse # APFS support (read-only)
    sqlite
    usbToggle
  ]
  # Affinity Suite — heavy creative app, workstation-only. Skipped on the
  # headless servers (vista, nuc), which also don't load the affinity-nix
  # overlay that defines it.
  ++ lib.optionals (!builtins.elem hostName [ "vista" "nuc" ]) [
    affinity-v3
  ];

  # Link thumbnailer files so file managers can find them
  environment.pathsToLink = [
    "share/thumbnailers"
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      openssl
    ];
  };
  programs.zsh.enable = true;
  programs.ssh = {
    startAgent = true;
    enableAskPassword = true;
    askPassword = "${pkgs.gnome-keyring}/bin/gnome-keyring-ask";
  };

  # Set zsh as the default shell for the system
  users.defaultUserShell = pkgs.zsh;

  networking.firewall = {
    enable = true;
    logRefusedConnections = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users."${vars.user.name}" = {
    isNormalUser = true;
    description = "${vars.user.fullname}";
    shell = pkgs.zsh; # Explicitly set zsh as the user's shell
    extraGroups = [
      "networkmanager"
      "wheel"
      "audio"
      "docker"
      "video"
      "libvirtd"
    ];
  };

  # Fingerprint authentication for sudo and login
  # Only enabled per-host where fprintd is available (see hosts/ledger/hardware.nix)

  # Allow user to toggle USB devices without password
  security.sudo.extraRules = [
    {
      users = [ vars.user.name ];
      commands = [
        {
          command = "/run/current-system/sw/bin/usb-toggle *";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Deauthorize Blue Snowball on plug-in (off by default)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0d8c", ATTR{idProduct}=="0005", ATTR{authorized}="0"
  '';

  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };
}
