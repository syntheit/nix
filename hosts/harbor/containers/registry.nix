# Docker Registry — private container registry for the Malli fleet.
# Mac Minis pull pre-built images from here instead of building locally.
#
# Access control:
#   Push — from personal Tailscale (your laptop): docker push harbor:5000/malli/cursor-runner:latest
#   Pull — from fleet VMs (Headscale): docker pull conduit:5000/malli/cursor-runner:latest
#          (conduit proxies to harbor:5000 over WireGuard)
#
# No auth — harbor's port 5000 is only reachable from personal Tailscale
# and WireGuard (conduit). Not exposed to the internet.

{ ... }:

{
  virtualisation.oci-containers.containers.registry = {
    image = "registry:2";
    ports = [ "5000:5000" ];  # Accessible on all interfaces — firewall trusts tailscale0 only
    volumes = [
      "/arespool/appdata/registry:/var/lib/registry"
    ];
    environment = {
      REGISTRY_STORAGE_DELETE_ENABLED = "true";
    };

  };
}
