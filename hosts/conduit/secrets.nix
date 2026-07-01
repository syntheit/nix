{ lib, ... }:

{
  sops.defaultSopsFile = ../../secrets/conduit.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.foyer_jwt_secret = { owner = "foyer"; };
  sops.secrets.foyer_api_key = { owner = "foyer"; };

  # Deus secrets — sops renders to /run/secrets, which is a host-only
  # tmpfs. The headscale container can't follow that symlink, so the
  # deus-stage activation script in headscale.nix copies the actual
  # file contents into bind-mounted paths.
  sops.secrets.deus_operator_token.mode = "0444";
  sops.secrets.deus_agent_token.mode = "0444";
  # Read-only by root, copied into the container and re-permissioned to
  # the fleet user there so SSH accepts it as an identity file.
  # Stored as its own binary-encrypted file to avoid YAML multi-line
  # escaping pain — the OpenSSH private key format has trailing newlines
  # and base64 wrapping that fight with `|` literal blocks.
  sops.secrets.deus_deploy_key = {
    sopsFile = ../../secrets/conduit/deus_deploy_key;
    format = "binary";
    mode = "0400";
  };

  # ── Granter master credentials ───────────────────────────
  # These let the deus-server inside the headscale container mint
  # per-device Cloudflare tunnels. The keys never leave conduit; only
  # the per-device derivatives are pushed back to malli-nix.
  # (Twilio master creds removed in deus 0.16.0.)
  sops.secrets.cloudflare_api_token.mode = "0444";
  # CF account + zone IDs aren't catastrophic to expose but the nix repo
  # is public, so keep them encrypted at rest alongside the API token.
  sops.secrets.cloudflare_account_id.mode = "0444";
  sops.secrets.cloudflare_zone_id.mode = "0444";
  # Separate binary-encoded SSH key — write-capable deploy key on the
  # malli-nix repo so the granter can push committed SOPS files.
  sops.secrets.deus_malli_nix_write_key = {
    sopsFile = ../../secrets/conduit/deus_malli_nix_write_key;
    format = "binary";
    mode = "0400";
  };

  # ── ADE orchestrator: nanomdm API key ────────────────────
  # deus-server's ADE orchestrator uses this both as the nanomdm enqueue
  # Basic-auth password and as the webhook ?token= secret it verifies.
  # It currently lives only in secrets/harbor.yaml (used by nanomdm on
  # harbor); the SAME value must be added to secrets/conduit.yaml so both
  # ends share it. Until then sops validation fails the conduit build and
  # the deus-stage script leaves the staged file absent (ADE stays off).
  sops.secrets.nanomdm_api.mode = "0444";

  # ── ADE bootstrap-creds vend: fleet age key ──────────────
  # The fleet sops age PRIVATE key deus-server vends to a bootstrapping
  # Mac (so its first darwin-rebuild can decrypt fleet secrets). Binary-
  # encoded in its own file to dodge YAML escaping. Gated with mkIf on
  # the encrypted file existing so sops validation doesn't fail the build
  # before Daniel adds it — see the gating note in headscale.nix.
  sops.secrets.deus_fleet_age_key = lib.mkIf (builtins.pathExists ../../secrets/conduit/deus_fleet_age_key) {
    sopsFile = ../../secrets/conduit/deus_fleet_age_key;
    format = "binary";
    mode = "0444";
  };
}
