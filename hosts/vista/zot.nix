# Zot OCI registry — Tart base/golden image cache for the Malli fleet.
# Migrated from harbor → vista (2026-08). Data lives on vista's local disk.
#
# Coexists with the docker-registry (:5000) — Zot handles `tart push/pull`
# (chunked OCI upload) which the docker-registry rejects. Fleet Macs reach it
# at `100.64.0.1:5001`, socat-forwarded over WireGuard to vista (10.100.0.4:5001).
# HTTP only; the WG hop + Headscale ACLs are the security boundary.
{ pkgs, ... }:

let
  zotConfig = pkgs.writeText "zot-config.json" (builtins.toJSON {
    storage.rootDirectory = "/var/lib/registry";
    http = {
      address = "0.0.0.0";
      port = "5000";
    };
    log.level = "info";
  });
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/zot 0755 root root -"
  ];

  virtualisation.oci-containers.containers.zot = {
    image = "ghcr.io/project-zot/zot-linux-amd64:latest";
    ports = [ "5001:5000" ];
    volumes = [
      "/var/lib/zot:/var/lib/registry"
      "${zotConfig}:/etc/zot/config.json:ro"
    ];
  };
}
