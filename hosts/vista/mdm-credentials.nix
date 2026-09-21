# Optional, coordinated NanoMDM/Deus credential cutover. The live v0.6 stack
# and its staging paths are unchanged unless explicitly enabled.
{ config, lib, pkgs, ... }:
let
  cfg = config.malli.mdm.privateCredentials;
  ddm = config.malli.mdm.declarativeManagement;
  staging = cfg.prepare || cfg.enable || cfg.retireLegacyWebhook;
  stageScript = pkgs.writeText "vista-mdm-stage-credentials.py"
    (builtins.readFile ../../packages/vista-mdm-stage-credentials.py);
in
{
  options.malli.mdm.privateCredentials = {
    prepare = lib.mkEnableOption "private MDM key staging and dual-method Deus ADE receiver, without switching NanoMDM";
    enable = lib.mkEnableOption "private file-backed NanoMDM API and signed ADE webhook credentials";
    hmacSopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        An independently generated, sops-encrypted binary file containing a
        32-256 byte printable ASCII webhook HMAC key. It must not reuse the API
        key. Leave null until the encrypted secret has been provisioned.
      '';
    };
    nanodepSopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Separately encrypted NanoDEP API key. Its v0.7 process still exposes
        that distinct key in argv; the old shared NanoMDM key must not be
        reused. This does not by itself satisfy full credential migration.
      '';
    };
    receiverVerified = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Explicit operator attestation that a reviewed and deployed Deus
        binary supports signed ADE webhooks. The live staged-key test occurs
        after prepare=true is deployed; that separate result is covered by
        prepareDeployedAndVerified. This is not the DDM bridge's broader
        credentialMigrationConfirmed attestation.
      '';
    };
    apiKeyVerified = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Explicit operator attestation that the staged file's exact bytes were
        verified against the existing NanoMDM API before switching away from
        the legacy environment/argument form.
      '';
    };
    prepareDeployedAndVerified = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Explicit operator attestation that a previous Nix generation with
        prepare=true was deployed, its staged files checked, and Deus accepted
        both legacy-only and signed test webhooks before NanoMDM cutover.
      '';
    };
    hmacTrafficVerified = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Explicit operator attestation that HMAC-only NanoMDM check-ins were
        observed healthy before removing Deus's legacy webhook credential.
      '';
    };
    retireLegacyWebhook = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        After HMAC-only NanoMDM traffic is proven healthy, stop Deus from
        accepting the legacy query bearer credential. Requires enable=true.
      '';
    };
  };

  config = lib.mkIf staging {
    assertions = [
      {
        assertion = cfg.hmacSopsFile != null;
        message = "Private MDM credentials require a separately encrypted webhook HMAC secret file.";
      }
      {
        assertion = cfg.nanodepSopsFile != null;
        message = "Private MDM credentials require a distinct NanoDEP API secret file; the old shared NanoMDM key must leave NanoDEP argv.";
      }
      {
        assertion = cfg.receiverVerified;
        message = "Private MDM credentials require an independently verified Deus signed-webhook receiver.";
      }
      {
        assertion = !cfg.enable || cfg.apiKeyVerified;
        message = "Private MDM credentials require an independently verified exact-byte NanoMDM API key.";
      }
      {
        assertion = !cfg.enable || (cfg.prepare && cfg.prepareDeployedAndVerified);
        message = "Private MDM cutover requires a separately deployed and verified receiver-first prepare generation.";
      }
      {
        assertion = !cfg.retireLegacyWebhook || (cfg.enable && cfg.hmacTrafficVerified);
        message = "Legacy ADE webhook auth cannot be retired before HMAC-only NanoMDM traffic is independently verified.";
      }
      {
        assertion = config.malli.mdm.deusDedicatedIdentity.enable
          && config.malli.mdm.deusDedicatedIdentity.migrationConfirmed;
        message = "Private MDM credentials require the separately approved dedicated Deus UID 3999 migration. This does not satisfy the DDM bridge's full credential-migration gate.";
      }
    ];

    # The old source is 0444 for the v0.6 env-file path. Tighten it only at
    # cutover, after the old consumer is being replaced, and keep the source
    # root-only for NanoDEP's existing root-owned env template.
    sops.secrets.nanomdm_api.mode = lib.mkForce "0600";
    sops.secrets.nanomdm_webhook_hmac_key = lib.mkIf (cfg.hmacSopsFile != null) {
      sopsFile = cfg.hmacSopsFile;
      format = "binary";
      mode = "0600";
    };
    sops.secrets.nanodep_api = lib.mkIf (cfg.nanodepSopsFile != null) {
      sopsFile = cfg.nanodepSopsFile;
      format = "binary";
      mode = "0600";
    };
    # Declarative-management pair. Only rendered when -dm is actually enabled:
    # an unused rendered secret is one more copy of key material on disk.
    sops.secrets.nanomdm_dm_send_hmac_key = lib.mkIf
      (ddm.enable && ddm.sendHmacSopsFile != null) {
        sopsFile = ddm.sendHmacSopsFile;
        format = "binary";
        mode = "0600";
      };
    sops.secrets.nanomdm_dm_recv_hmac_key = lib.mkIf
      (ddm.enable && ddm.recvHmacSopsFile != null) {
        sopsFile = ddm.recvHmacSopsFile;
        format = "binary";
        mode = "0600";
      };

    # Called at activation after sops renders both secrets. This writes only
    # exact-byte private copies; no credential value enters Nix/store/argv.
    system.activationScripts.vista-mdm-stage-credentials = {
      deps = [ "setupSecrets" ];
      text = ''
        ${pkgs.python3}/bin/python3 ${stageScript} \
          /run/secrets/nanomdm_api \
          /run/secrets/nanomdm_webhook_hmac_key \
          /run/secrets/nanodep_api \
          /var/lib/mdm/credentials \
          /var/lib/deus-tokens/private-mdm \
          /var/lib/deus-tokens/nanomdm-api${
            lib.optionalString (ddm.enable && ddm.sendHmacSopsFile != null
              && ddm.recvHmacSopsFile != null) '' \
          /run/secrets/nanomdm_dm_send_hmac_key \
          /run/secrets/nanomdm_dm_recv_hmac_key''}
      '';
    };
  };
}
