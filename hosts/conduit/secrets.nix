{ ... }:

{
  sops.defaultSopsFile = ../../secrets/conduit.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # ── Foyer dashboard ──────────────────────────────────────
  # Consumed by services.foyer in default.nix.
  sops.secrets.foyer_jwt_secret = { owner = "foyer"; };
  sops.secrets.foyer_api_key = { owner = "foyer"; };

  # ── user-vpn granter operator token ──────────────────────
  # The ONLY deus secret still consumed on conduit post-vista-migration —
  # hosts/conduit/user-vpn.nix reads it as the granter's operator bearer token.
  #
  # Everything else the old in-nspawn deus-server used (agent/service tokens,
  # the cloudflare granter creds, the nanomdm ADE key + fleet age key, and the
  # malli-deus / malli-nix git deploy keys) moved to vista with the nspawn and
  # is re-keyed under secrets/vista*. Those conduit sops entries were removed
  # here so the relay no longer decrypts them. Their ciphertext still sits in
  # secrets/conduit.yaml and secrets/conduit/* (harmless, unreferenced) — clean
  # those from the sops files on conduit later if desired.
  sops.secrets.deus_operator_token.mode = "0444";
}
