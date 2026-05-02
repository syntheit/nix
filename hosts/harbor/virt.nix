{ config, pkgs, lib, ... }:

# =====================================================================
# libvirt / QEMU / KVM — VM playground
#
# Storage layout
#   /micron01/vms/disks      active VM disks (Crucial SSD)
#   /platapool/vms/templates golden base images
#   /platapool/vms/isos      OS install media (drop ISOs here)
#
# Workflow (from mantle)
#   1. Drop an ISO into /platapool/vms/isos/  (scp / Samba / whatever)
#   2. virt-manager → File → Add Connection → QEMU/KVM, hostname:
#        matv@harbor.lan   (uses qemu+ssh:// on port 64829)
#   3. New VM → choose Local install media → pick ISO from `isos` pool →
#      pick `disks` pool for the new disk image → install.
#   4. Connect to console with the embedded SPICE viewer.
#
# Save a "golden" base after install (so you can reset later)
#   virsh shutdown <vm>
#   cp /micron01/vms/disks/<vm>.qcow2 /platapool/vms/templates/<vm>-base.qcow2
#
# Reset to clean state (instant — qcow2 backing-file overlay)
#   virsh destroy <vm> 2>/dev/null || true
#   rm /micron01/vms/disks/<vm>.qcow2
#   qemu-img create -f qcow2 -F qcow2 \
#     -b /platapool/vms/templates/<vm>-base.qcow2 \
#     /micron01/vms/disks/<vm>.qcow2
#   virsh start <vm>
#
# Windows guests
#   The virtio-win ISO is at ${pkgs.virtio-win}/share/virtio-win/virtio-win.iso
#   Mount it as a second CD during install for storage/network drivers.
# =====================================================================

{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
    onBoot = "ignore";
    onShutdown = "shutdown";
  };

  virtualisation.spiceUSBRedirection.enable = true;

  users.users.matv.extraGroups = [ "libvirtd" "kvm" ];

  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    qemu_kvm
    OVMFFull
    swtpm
    spice-gtk
    spice-protocol
    virtio-win
    win-spice
    libguestfs
    dnsmasq                          # required by libvirt's default NAT network for DHCP/DNS
  ];

  # libvirt-dbus — required by cockpit-machines (its manifest checks for
  # /etc/systemd/system/libvirt-dbus.service before exposing the VMs page).
  # Not packaged as a NixOS module. services.dbus.packages doesn't aggregate
  # this on dbus-broker setups, and environment.etc collides with another
  # module's /etc/dbus-1 symlink, so we drop the policy + activation files
  # via tmpfiles at activation time.
  services.dbus.packages = [ pkgs.libvirt-dbus ];

  users.users.libvirtdbus = {
    isSystemUser = true;
    group = "libvirtdbus";
    extraGroups = [ "qemu-libvirtd" "libvirtd" ];
    description = "libvirt-dbus service account";
  };
  users.groups.libvirtdbus = { };

  systemd.services.libvirt-dbus = {
    description = "Libvirt DBus Service";
    after = [ "libvirtd.service" "dbus.service" ];
    wants = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      BusName = "org.libvirt";
      User = "libvirtdbus";
      Group = "libvirtdbus";
      ExecStart = "${pkgs.libvirt-dbus}/bin/libvirt-dbus --system";
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.libvirt.unix.manage" && subject.user == "libvirtdbus") {
        return polkit.Result.YES;
      }
    });
  '';

  # Cockpit web UI — browser-based VM management. Tailscale-only access
  # (firewall not opened; reachable on harbor:9099 via tailscale0).
  services.cockpit = {
    enable = true;
    port = 9099;                   # 9090 = Prometheus, 9091 = docker-proxy, 9100 = node_exporter
    openFirewall = false;
    plugins = [ pkgs.cockpit-machines ];
    settings.WebService = {
      AllowUnencrypted = true;     # plain HTTP over Tailscale (encrypted by WG)
      Origins = lib.mkForce "https://localhost:9099 http://localhost:9099 https://harbor:9099 http://harbor:9099 https://harbor.lan:9099 http://harbor.lan:9099";
    };
  };

  systemd.tmpfiles.rules = [
    "L+ /var/lib/qemu/firmware - - - - ${pkgs.qemu}/share/qemu/firmware"
    # /micron01 is matv-owned but qemu-libvirtd needs to traverse it.
    "z /micron01 0755 - - - -"
    "d /micron01/vms 0755 root root - -"
    "d /micron01/vms/disks 0775 root libvirtd - -"
    "d /platapool/vms 0755 root root - -"
    "d /platapool/vms/templates 0775 root libvirtd - -"
    "d /platapool/vms/isos 0775 root libvirtd - -"
  ];

  # Define libvirt storage pools so they show up in virt-manager.
  # Idempotent: skipped if pool already exists.
  systemd.services.libvirt-pools-init = {
    description = "Define libvirt storage pools (disks/templates/isos)";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = [ "/micron01" "/platapool" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = let virsh = "${pkgs.libvirt}/bin/virsh"; in ''
      define_pool() {
        local name=$1
        local path=$2
        if ! ${virsh} pool-info "$name" >/dev/null 2>&1; then
          ${virsh} pool-define-as --name "$name" --type dir --target "$path"
          ${virsh} pool-build "$name" || true
          ${virsh} pool-autostart "$name"
          ${virsh} pool-start "$name" || true
        fi
      }
      define_pool disks     /micron01/vms/disks
      define_pool templates /platapool/vms/templates
      define_pool isos      /platapool/vms/isos

      # Ensure the built-in NAT network 'default' is autostarted + running.
      ${virsh} net-autostart default 2>/dev/null || true
      ${virsh} net-start default 2>/dev/null || true
    '';
  };

  # SPICE/VNC bind to 127.0.0.1 by default. Remote clients reach them via
  # SSH tunnel (qemu+ssh:// for virt-manager, "Use SSH tunnel" in aSPICE Pro).
  # AllowTcpForwarding=yes is already set in access.nix/default.nix.
}
