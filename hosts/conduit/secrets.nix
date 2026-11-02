{ ... }:

{
  sops.defaultSopsFile = ../../secrets/conduit.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # ── Foyer dashboard ──────────────────────────────────────
  # Consumed by services.foyer in default.nix.
  sops.secrets.foyer_jwt_secret = { owner = "foyer"; };
  sops.secrets.foyer_api_key = { owner = "foyer"; };

  # No Malli secrets are consumed on conduit since the user VPN was retired (2026-11-02);
  # old ciphertext in secrets/conduit.yaml and secrets/conduit/* is unreferenced.
}
