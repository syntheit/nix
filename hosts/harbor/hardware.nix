{
  config,
  pkgs,
  ...
}:

{
  # Boot configuration
  boot = {
    loader.systemd-boot.enable = true;
    loader.systemd-boot.configurationLimit = 20;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [ "zfs" ];
    blacklistedKernelModules = [ "nouveau" ];
    kernelParams = [
      "i915.enable_guc=2"
      "zfs.zfs_arc_max=17179869184" # 16GB — reduced from 32GB to eliminate swap pressure
      "zfs.zfs_arc_min=4294967296" # 4GB — metadata floor for 8 pools / 102TB
      "zfs.zfs_arc_sys_free=4294967296" # 4GB — ARC shrinks when free RAM below this
    ];
    zfs = {
      forceImportRoot = false;
      extraPools = [
        "arespool"
        "lambdapool"
        "iotapool"
        "thetapool"
        "deltapool"
        "epsilpool"
        "rhopool"
        "platapool"
      ];
    };
    # tmpfs for /tmp — reduces SSD writes
    tmp.useTmpfs = true;
    tmp.tmpfsSize = "16G";
    # Server-tuned sysctl
    kernel.sysctl = {
      "vm.min_free_kbytes" = 524288; # 512MB — start reclaiming early to avoid stalls
      "vm.swappiness" = 10; # Low — prefer reclaiming ZFS ARC over swapping
      "vm.vfs_cache_pressure" = 50; # ZFS handles its own caching
      "vm.dirty_bytes" = 268435456; # 256MB — flush dirty pages at fixed thresholds
      "vm.dirty_background_bytes" = 67108864; # 64MB
      # BBR congestion control — better for WireGuard tunnel + streaming
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
      # Increase buffers for WireGuard throughput
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_fastopen" = 3;
    };
  };

  # GPU drivers — headless server, no X11 needed
  # nvidia driver required for container toolkit (Jellyfin GPU transcoding)
  services.xserver.videoDrivers = [ "nvidia" "intel" ];

  # Hardware configuration
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = false;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };
    cpu.intel.updateMicrocode = true;
    nvidia = {
      modesetting.enable = true;
      open = true;
      nvidiaSettings = false; # No GUI on a headless server
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };
    nvidia-container-toolkit.enable = true;
  };
}
