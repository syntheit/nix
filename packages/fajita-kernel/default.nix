# Vendored from mobile-nixos devices/families/sdm845-mainline/kernel — same
# builder + configfile logic, DIFFERENT SOURCE: the mwlaboratories fork pins
# a raw linux-next snapshot (6.19.0-rc4-next-20260106) where Q6/SLIMbus mic
# CAPTURE is broken (pure digital-zero recordings; playback fine). This pins
# the sdm845-mainline CURATED tree at the exact tag pmOS ships with fully
# working fajita audio (sdm845-6.16.7-r0). Deltas vs upstream we want: the
# tfa9894 speaker-amp DT node + QUAT_MI2S dai-link (upstream /delete-node/s
# the speaker!) and SLIM_QCOM_NGD_CTRL=y built-in. Vendored (not overridden)
# because the configfile sub-derivation closes over kernelSrc.
{
  mobile-nixos,
  fetchFromGitLab,
  stdenv,
  buildPackages,
  ...
}:

let
  # NB: the tree's sdm845.config sets CONFIG_LOCALVERSION="-sdm845" but the
  # kernel-builder normalizes it away — kernelrelease comes out plain 6.16.7
  # (build fails with the right value in the error if this ever drifts).
  version = "6.16.7";

  kernelSrc = fetchFromGitLab {
    owner = "sdm845-mainline";
    repo = "linux";
    rev = "c4804e960aef0f399cd5417c3a522d1c191285b0"; # tag sdm845-6.16.7-r0
    sha256 = "06b6hhzlj9fq65jsyx441b48zb3gyknbmslv9qifpfd96sxmg2ax";
  };

  configfile = stdenv.mkDerivation {
    name = "sdm845-kernel-config";
    src = kernelSrc;

    nativeBuildInputs = [
      buildPackages.gnumake
      buildPackages.gcc
      buildPackages.bc
      buildPackages.bison
      buildPackages.flex
      buildPackages.perl
      buildPackages.python3
    ];

    buildPhase = ''
            export ARCH=arm64
            export KCONFIG_CONFIG=$PWD/.config

            # Start with defconfig
            make defconfig

            # Merge sdm845.config fragment if it exists
            if [ -f arch/arm64/configs/sdm845.config ]; then
              scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/sdm845.config
            fi

            # Add essential NixOS required kernel options
            cat >> .config <<EOF
      # NixOS required options
      CONFIG_DEVTMPFS=y
      CONFIG_CGROUPS=y
      CONFIG_INOTIFY_USER=y
      CONFIG_SIGNALFD=y
      CONFIG_TIMERFD=y
      CONFIG_EPOLL=y
      CONFIG_NET=y
      CONFIG_SYSFS=y
      CONFIG_PROC_FS=y
      CONFIG_FHANDLE=y
      CONFIG_CRYPTO_HMAC=y
      CONFIG_CRYPTO_SHA256=y
      CONFIG_CRYPTO_USER_API_HASH=y
      CONFIG_TMPFS_POSIX_ACL=y
      CONFIG_TMPFS_XATTR=y
      CONFIG_SECCOMP=y
      CONFIG_TMPFS=y
      CONFIG_BLK_DEV_INITRD=y
      CONFIG_BINFMT_ELF=y
      CONFIG_UNIX=y

      # Android/Mobile specific
      CONFIG_ANDROID_BINDERFS=y

      # Networking and netfilter
      CONFIG_XFRM=y
      CONFIG_XFRM_ALGO=y
      CONFIG_XFRM_USER=y
      CONFIG_NF_CONNTRACK=y
      CONFIG_NF_CONNTRACK_ZONES=y
      CONFIG_NF_CONNTRACK_TIMEOUT=y
      CONFIG_NF_CONNTRACK_TIMESTAMP=y
      CONFIG_NF_CONNTRACK_BRIDGE=y
      CONFIG_NF_CT_NETLINK=y
      CONFIG_NF_TABLES=y
      CONFIG_NF_TABLES_ARP=y
      CONFIG_NF_TABLES_NETDEV=y
      CONFIG_NF_DUP_NETDEV=y
      CONFIG_NF_TPROXY_IPV4=y
      CONFIG_NETFILTER_NETLINK=y
      CONFIG_NETFILTER_NETLINK_GLUE_CT=y
      CONFIG_NETFILTER_NETLINK_LOG=y
      CONFIG_NETFILTER_NETLINK_QUEUE=y
      CONFIG_NETFILTER_XTABLES=y
      CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
      CONFIG_NETFILTER_XT_MATCH_BPF=y
      CONFIG_NETFILTER_XT_MATCH_CGROUP=y
      CONFIG_NETFILTER_XT_MATCH_CLUSTER=y
      CONFIG_NETFILTER_XT_MATCH_COMMENT=y
      CONFIG_NETFILTER_XT_MATCH_CONNBYTES=y
      CONFIG_NETFILTER_XT_MATCH_CONNLABEL=y
      CONFIG_NETFILTER_XT_MATCH_CONNLIMIT=y
      CONFIG_NETFILTER_XT_MATCH_CONNMARK=y
      CONFIG_NETFILTER_XT_MATCH_CONNTRACK=y
      CONFIG_NETFILTER_XT_MATCH_CPU=y
      CONFIG_NETFILTER_XT_MATCH_DCCP=y
      CONFIG_NETFILTER_XT_MATCH_DEVGROUP=y
      CONFIG_NETFILTER_XT_MATCH_DSCP=y
      CONFIG_NETFILTER_XT_MATCH_ECN=y
      CONFIG_NETFILTER_XT_MATCH_ESP=y
      CONFIG_NETFILTER_XT_MATCH_HELPER=y
      CONFIG_NETFILTER_XT_MATCH_HL=y
      CONFIG_NETFILTER_XT_MATCH_IPCOMP=y
      CONFIG_NETFILTER_XT_MATCH_IPRANGE=y
      CONFIG_NETFILTER_XT_MATCH_L2TP=y
      CONFIG_NETFILTER_XT_MATCH_LENGTH=y
      CONFIG_NETFILTER_XT_MATCH_LIMIT=y
      CONFIG_NETFILTER_XT_MATCH_MAC=y
      CONFIG_NETFILTER_XT_MATCH_MARK=y
      CONFIG_NETFILTER_XT_MATCH_MULTIPORT=y
      CONFIG_NETFILTER_XT_MATCH_NFACCT=y
      CONFIG_NETFILTER_XT_MATCH_OSF=y
      CONFIG_NETFILTER_XT_MATCH_OWNER=y
      CONFIG_NETFILTER_XT_MATCH_PKTTYPE=y
      CONFIG_NETFILTER_XT_MATCH_POLICY=y
      CONFIG_NETFILTER_XT_MATCH_QUOTA=y
      CONFIG_NETFILTER_XT_MATCH_RATEEST=y
      CONFIG_NETFILTER_XT_MATCH_REALM=y
      CONFIG_NETFILTER_XT_MATCH_RECENT=y
      CONFIG_NETFILTER_XT_MATCH_SCTP=y
      CONFIG_NETFILTER_XT_MATCH_STATE=y
      CONFIG_NETFILTER_XT_MATCH_STATISTIC=y
      CONFIG_NETFILTER_XT_MATCH_STRING=y
      CONFIG_NETFILTER_XT_MATCH_TCPMSS=y
      CONFIG_NETFILTER_XT_MATCH_TIME=y
      CONFIG_NETFILTER_XT_MATCH_U32=y
      CONFIG_NETFILTER_XT_TARGET_CT=y
      CONFIG_NETFILTER_XT_TARGET_NFLOG=y
      CONFIG_NFT_COMPAT=y
      CONFIG_NFT_CONNLIMIT=y
      CONFIG_NFT_CT=y
      CONFIG_NFT_DUP_NETDEV=y
      CONFIG_NFT_FWD_NETDEV=y
      CONFIG_NFT_HASH=y
      CONFIG_NFT_LIMIT=y
      CONFIG_NFT_LOG=y
      CONFIG_NFT_MASQ=y
      CONFIG_NFT_NAT=y
      CONFIG_NFT_NUMGEN=y
      CONFIG_NFT_OSF=y
      CONFIG_NFT_QUOTA=y
      CONFIG_NFT_REDIR=y
      CONFIG_NFT_SYNPROXY=y
      CONFIG_NFT_TUNNEL=y
      CONFIG_IP_NF_IPTABLES=y
      CONFIG_IP_NF_RAW=y

      # HID sensors
      CONFIG_HID_SENSOR_HUB=y
      CONFIG_HID_SENSOR_IIO_COMMON=y
      CONFIG_HID_SENSOR_ACCEL_3D=y
      CONFIG_HID_SENSOR_ALS=y
      CONFIG_HID_SENSOR_GYRO_3D=y
      CONFIG_HID_SENSOR_MAGNETOMETER_3D=y
      CONFIG_HID_SENSOR_INCLINOMETER_3D=y
      CONFIG_HID_SENSOR_DEVICE_ROTATION=y
      CONFIG_HID_SENSOR_HUMIDITY=y
      CONFIG_HID_SENSOR_TEMP=y
      CONFIG_HID_SENSOR_CUSTOM_INTEL_HINGE=y
      CONFIG_HID_SENSOR_PRESS=y
      CONFIG_HID_SENSOR_PROX=y

      CONFIG_GPIO_SHARED_PROXY=y

      # Defer fbcon takeover so the bootloader cont_splash (our LOGO-partition
      # flake) stays on the panel and plymouth (DRM) owns the display. Without
      # this, fbcon grabs the framebuffer the instant the kernel boots, prints
      # console text over the splash, and plymouth renders INVISIBLY — the root
      # cause of the "initial text then black" boot (diagnosed 2026-08-21). This
      # is the standard NixOS-with-plymouth setting; mobile-nixos left it off
      # assuming a kernel fbcon logo as the early splash, which this device's
      # bootloader simplefb can't blit anyway.
      CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y

      # Disable LOCALVERSION_AUTO to make modDirVersion predictable
      CONFIG_LOCALVERSION_AUTO=n
      EOF

            # Run olddefconfig to resolve dependencies
            make olddefconfig

            cp .config config
    '';

    installPhase = ''
      cp config $out
    '';
  };
in

mobile-nixos.kernel-builder {
  inherit version;
  configfile = configfile;
  src = kernelSrc;

  patches = [
    # BOTH panel/display patches below are DISABLED after two failed flash
    # attempts (2026-07-18) — full postmortem in
    # ~/fajita-notes/power-button-brightness.md. Do NOT re-enable and flash
    # without reworking; the stock kernel is the known-good daily driver.
    #
    # DISABLED — kills the DSI link: adopting 6.18.2's rails-off-on-blank flow
    # on our 6.16.7 base leaves every subsequent DCS transfer timing out
    # (-110) after the first blank; even the verify-retry can't recover a dead
    # link. Rework planned: keep the normal path byte-identical to stock, add
    # ONLY GET_POWER_MODE verify + reset-pulse retry on provable failure.
    # ./patches/panel-s6e3fc2x01-verify-retry.patch
    # DISABLED 2026-07-18 — BREAKS BOOT on this 6.16 tree: with
    # CLK_OPS_PARENT_ENABLE the clk core enables the DSI PHY PLL during early
    # RCG ops, before the PHY driver has configured it -> "DSI PLL(0) lock
    # failed" at dsi_phy_driver_probe -> display dead from power-on (flashed,
    # confirmed, rolled back). Upstream landed on 6.20 where the companion
    # rcg2/DSI guards exist; re-attempt only together with those prerequisites.
    # Patch kept for that future backport. (It fixes rare random freezes /
    # crashdumps on OP6/6T — mainline a1d63493634e.)
    # ./patches/dispcc-sdm845-pixel-clk-parent-enable.patch
  ];

  nativeBuildInputs = [ buildPackages.python3 buildPackages.zstd buildPackages.kmod ];

  # Skip "install" (zinstall for boot files) but keep modules_install (runs depmod)
  installTargets = [ "modules_install" ];

  postInstall = ''
    # Manually copy the kernel image
    echo ":: Installing Image.gz kernel"
    cp -v "$buildRoot/arch/arm64/boot/Image.gz" "$out/Image.gz"

    # Create symlink for compatibility
    ln -sv Image.gz "$out/vmlinuz" || true

    # Explicitly run depmod to generate modules.dep, modules.alias, etc.
    # Cross-compilation causes make modules_install's depmod to silently fail.
    echo ":: Running depmod to generate module dependency files"
    depmod -b "$out" -F "$buildRoot/System.map" "${version}"
  '';

  isModular = true;
  modDirVersion = version;
  isCompressed = "gz";
}
