# Docker Registry — private container registry for the Malli fleet.
# Mac Minis pull pre-built images from here instead of building locally.
#
# Access control: Tailscale only. The registry binds to harbor's Tailscale
# IP, so only machines on the tailnet can reach it. No passwords needed.
#
# Push (from your laptop or CI, must be on tailnet):
#   docker push harbor:5000/malli/cursor-runner:latest
#
# Pull (from Mac Mini VMs, on tailnet):
#   docker pull harbor:5000/malli/cursor-runner:latest

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
    labels = {
      "com.centurylinklabs.watchtower.enable" = "true";
    };
  };
}
