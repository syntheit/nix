{ inputs, pkgs, ... }:

# Static site: the vestal website (https://vestal.matv.io).
# Served by nginx on 127.0.0.1:8099 and exposed publicly via the harbor
# cloudflared tunnel (ingress in access.nix). One-time DNS CNAME:
#   cloudflared tunnel route dns harbor vestal.matv.io
#
# The content is the `site` package of the vestal flake input (built offline
# from the vestal repo), so updating it is `nix flake update vestal` and a
# rebuild. Versioned URLs (?v=...) and the font, icon and shader files are
# immutable; HTML revalidates after five minutes.

{
  services.nginx = {
    enable = true;
    appendHttpConfig = ''
      map $arg_v $vestal_cache_control {
        default "public, max-age=300";
        "~.+"   "public, max-age=31536000, immutable";
      }
    '';
    virtualHosts."vestal-site" = {
      listen = [ { addr = "127.0.0.1"; port = 8099; } ];
      root = inputs.vestal.packages.${pkgs.stdenv.hostPlatform.system}.site;
      locations."/" = {
        index = "index.html";
        tryFiles = "$uri $uri/ $uri.html =404";
        extraConfig = ''
          add_header Cache-Control $vestal_cache_control;
        '';
      };
      locations."~* ^/assets/.*\\.(woff2?|ttf|otf|glsl)$".extraConfig = ''
        add_header Cache-Control "public, max-age=31536000, immutable";
      '';
      extraConfig = ''
        gzip on;
        gzip_vary on;
        gzip_comp_level 6;
        gzip_types text/plain text/css text/xml application/json application/javascript text/javascript image/svg+xml;
      '';
    };
  };
}
