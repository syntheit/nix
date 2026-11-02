# Malli control plane moved from vista to the colo NUC on 2026-11-01.
# See ~/malli-plans/nuc-research/HANDOFF-1101.md.
#
# Everything below is STOPPED on vista and must never auto-start again: a
# vista reboot would otherwise start a second Headscale + deus with the same
# tailnet node key (split brain). This file only removes boot-time start
# (autoStart / wantedBy); it deliberately leaves the unit definitions alone so
# `nixos-rebuild switch` neither starts nor needlessly restarts anything.
# zot, docker-registry, invidious and wg0 are NOT touched.
#
# TODO: delete these services (and this file) next week.
{ lib, ... }:
{
  # nixos-container: headscale, deus-server, tailscaled, cloudflared, git-daemon,
  # caddy and the mirror/recover timers all live inside it.
  containers.headscale.autoStart = lib.mkForce false;

  # Host-side console.
  systemd.services.malli-web.wantedBy = lib.mkForce [ ];

  # MDM stack (docker oci-containers).
  virtualisation.oci-containers.containers = {
    nanomdm.autoStart = lib.mkForce false;
    scep.autoStart = lib.mkForce false;
    mdmenroll.autoStart = lib.mkForce false;
    nanodep.autoStart = lib.mkForce false;
    deus-ddm-bridge.autoStart = lib.mkForce false;
  };
}
