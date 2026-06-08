# Zot OCI registry — Tart base/golden image cache for the Malli fleet.
#
# Why a second registry: the existing docker-registry:2 on :5000 works fine
# for container images (orchestrator, cursor-runner, dashboard) but rejects
# `tart push` with MANIFEST_UNKNOWN — chunked-upload / cross-mount-blob OCI
# flow incompatibility. Zot is the registry the Tart team uses in their own
# tested examples, with cleaner OCI v1.0/v1.1 compliance. Coexists with the
# docker-registry rather than replacing it so fleet container pulls stay
# undisturbed.
#
# Access shape mirrors docker-registry:
#   Push — from any Mac that already has the cirruslabs image (m-qvlm,
#          m-pg4i, m-g94t) on personal Tailscale:
#            tart push --insecure --chunk-size 4 \
#              ghcr.io/cirruslabs/macos-sequoia-base:latest \
#              100.64.0.1:5001/malli/macos-sequoia-base:v1
#   Pull — from fleet Macs via conduit's :5001 socat over WireGuard:
#            tart pull --insecure 100.64.0.1:5001/malli/macos-sequoia-base:v1
#
# HTTP only. The WG hop + headscale ACLs are the security boundary; harbor's
# firewall trusts wg0 / tailscale0 only.

{ pkgs, ... }:

let
  # Minimal zot config: storage on /arespool, HTTP on the container's
  # internal :5000 (mapped to host :5001), no auth. Logging at info so we
  # can spot push failures in `journalctl -u docker-zot`.
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
    "d /arespool/appdata/zot 0755 root root -"
  ];

  virtualisation.oci-containers.containers.zot = {
    image = "ghcr.io/project-zot/zot-linux-amd64:latest";
    ports = [ "5001:5000" ];
    volumes = [
      "/arespool/appdata/zot:/var/lib/registry"
      "${zotConfig}:/etc/zot/config.json:ro"
    ];
  };
}
