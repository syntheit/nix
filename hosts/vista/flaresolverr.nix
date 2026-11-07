{ ... }:
{
  # FlareSolverr for the hunt engine (~/Projects/hunt): solves Cloudflare/WAF challenges for the
  # listing portals Daniel authorized (Zonaprop, Argenprop). Stateless; localhost only.
  # Capped so Chromium bursts don't heat the MacBook: 2 CPUs, 2 GB.
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:v3.5.2";
    environment = {
      TZ = "America/Argentina/Buenos_Aires";
      LOG_LEVEL = "info";
    };
    ports = [ "127.0.0.1:8191:8191" ];
    extraOptions = [
      "--cpus=2"
      "--memory=2g"
    ];
  };
}
