{ ... }:

# Static site: the Malli fleet system-overview doc for the team.
# Served by nginx on :8098 and exposed publicly via the harbor cloudflared
# tunnel as https://malli-overview.matv.io (ingress in access.nix; the DNS
# CNAME was created with `cloudflared tunnel route dns harbor malli-overview.matv.io`).
#
# The site content lives in ./malli-overview/ (index.html + deus-*.png) and is
# copied into the Nix store, so nginx serves a read-only, reproducible copy.
# To update the page: edit files in ./malli-overview/ and rebuild.

{
  services.nginx = {
    enable = true;
    virtualHosts."malli-overview" = {
      listen = [ { addr = "0.0.0.0"; port = 8098; } ];
      root = ./malli-overview;
      locations."/".index = "index.html";
    };
  };
}
