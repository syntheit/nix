# Docker Registry — private container registry for the Malli fleet.
# Migrated from harbor → vista (2026-08). Data lives on vista's local disk.
#
# Access shape is unchanged from the fleet's point of view: Macs pull from
# `conduit:5000` / `100.64.0.1:5000`, which conduit socat-forwards over
# WireGuard to vista (10.100.0.4:5000). No auth — reachable only from the
# WireGuard link and personal Tailscale, never the internet (vista's firewall
# trusts wg0 / tailscale0 only).
{ ... }:

{
  systemd.tmpfiles.rules = [
    "d /var/lib/registry 0755 root root -"
  ];

  virtualisation.oci-containers.containers.registry = {
    image = "registry:2";
    ports = [ "5000:5000" ]; # firewall trusts wg0/tailscale0 only
    volumes = [
      "/var/lib/registry:/var/lib/registry"
    ];
    environment = {
      REGISTRY_STORAGE_DELETE_ENABLED = "true";
    };
  };
}
