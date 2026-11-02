# Switchboard: where conduit relays each Mac-facing service (vista or the colo
# NUC), plus an optional second WireGuard spoke for the NUC.
#
# Defaults reproduce the pre-switchboard system exactly (everything -> vista,
# no NUC peer). Flip one service = change one option below and redeploy.
#
# Reload behaviour (why flips do not disturb other services):
#   - socat forwarders (registry, zot, deus, git, operatorSsh, nanomdm) are
#     separate systemd units; a switch restarts only the unit whose ExecStart
#     changed, so only that service's open connections drop.
#   - Caddy is reloaded gracefully (`caddy reload`, not restart): new requests
#     use the new upstream at once, in-flight requests finish. Long-lived
#     streams on a changed handler (headscale long-polls) reconnect; Macs
#     retry on their own.
#   - The NUC peer is added at runtime by its own oneshot unit (`wg set`), NOT
#     through networking.wg-quick, because wg-quick-wg0 has no reload and
#     changing its config restarts wg0 (drops harbor, vista, everything).
{ config, lib, pkgs, ... }:

let
  cfg = config.malli.conduit;
  svc = _: lib.mkOption {
    type = lib.types.enum [ "vista" "nuc" ];
    default = "vista";
    description = "Which host conduit relays this service to.";
  };
  wg = "${pkgs.wireguard-tools}/bin/wg";
in
{
  options.malli.conduit = {
    nucWgAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.100.0.5";
      description = "NUC's address on wg0 (the upstream when a service is set to \"nuc\").";
    };
    nucWgPublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "NUC's WireGuard public key. null = no NUC peer on conduit.";
    };
    upstream = {
      headscale = svc "vista"; # :8085 headscale.matv.io
      deus = svc "vista"; # :8086 bootstrap.matv.io /ade/* /healthz, socat 100.64.0.1 + 10.100.0.1 hairpin
      bootstrapPkg = svc "vista"; # :8088 bootstrap.matv.io /pkg/*
      git = svc "vista"; # :9418
      registry = svc "vista"; # :5000
      zot = svc "vista"; # :5001
      operatorSsh = svc "vista"; # :2222
      nanomdm = svc "vista"; # :9990 mdm.matv.io, socat 10.100.0.1 hairpin
      scep = svc "vista"; # :8081 scep.matv.io
      mdmenroll = svc "vista"; # :9991 enroll.matv.io
    };
  };

  config = lib.mkIf (cfg.nucWgPublicKey != null) {
    systemd.services.wg-nuc-peer = {
      description = "WireGuard peer for the colo NUC on wg0 (runtime add, no wg0 restart)";
      after = [ "wg-quick-wg0.service" ];
      requires = [ "wg-quick-wg0.service" ];
      partOf = [ "wg-quick-wg0.service" ];
      wantedBy = [ "wg-quick-wg0.service" "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # No endpoint: the NUC dials out from behind colo NAT.
        ExecStart = "${wg} set wg0 peer ${cfg.nucWgPublicKey} allowed-ips ${cfg.nucWgAddress}/32";
        ExecStop = "-${wg} set wg0 peer ${cfg.nucWgPublicKey} remove";
      };
    };
  };
}
