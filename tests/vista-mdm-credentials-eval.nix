{ vista }:
let
  off = vista.config;
  blocked = (vista.extendModules {
    modules = [ ({ ... }: { malli.mdm.privateCredentials.enable = true; }) ];
  }).config;
  blockedMessages = map (item: item.message)
    (builtins.filter (item: !item.assertion) blocked.assertions);
  prepared = (vista.extendModules {
    modules = [ ({ ... }: {
      malli.mdm.deusDedicatedIdentity = {
        enable = true;
        migrationConfirmed = true; # evaluation fixture only
      };
      malli.mdm.privateCredentials = {
        prepare = true;
        hmacSopsFile = ../secrets/vista/deus_deploy_key;
        nanodepSopsFile = ../secrets/vista/malli_nix_deploy_key;
        receiverVerified = true;
      };
    }) ];
  }).config;
  pin = {
    owner = "offline-test-only";
    repo = "nanomdm";
    rev = "0000000000000000000000000000000000000000";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  onSystem = vista.extendModules {
    modules = [ ({ ... }: {
      malli.mdm.nanomdmPatchedSourcePin = pin;
      malli.mdm.deusDedicatedIdentity = {
        enable = true;
        migrationConfirmed = true; # evaluation only; never deploy this fixture
      };
      malli.mdm.privateCredentials = {
        prepare = true;
        enable = true;
        hmacSopsFile = ../secrets/vista/deus_deploy_key;
        nanodepSopsFile = ../secrets/vista/malli_nix_deploy_key;
        receiverVerified = true; # evaluation only
        apiKeyVerified = true; # evaluation only
        prepareDeployedAndVerified = true; # evaluation only
      };
    }) ];
  };
  on = onSystem.config;
  unverifiedPrepare = (onSystem.extendModules {
    modules = [ ({ lib, ... }: {
      malli.mdm.privateCredentials.prepareDeployedAndVerified = lib.mkForce false;
    }) ];
  }).config;
  unverifiedRetirement = (onSystem.extendModules {
    modules = [ ({ ... }: { malli.mdm.privateCredentials.retireLegacyWebhook = true; }) ];
  }).config;
  verifiedRetirement = (onSystem.extendModules {
    modules = [ ({ ... }: {
      malli.mdm.privateCredentials.retireLegacyWebhook = true;
      malli.mdm.privateCredentials.hmacTrafficVerified = true;
    }) ];
  }).config;
  # Declarative management asked for on its own: every prerequisite must
  # refuse it by name, and nothing about the live stack may change.
  ddmBlocked = (vista.extendModules {
    modules = [ ({ ... }: { malli.mdm.declarativeManagement.enable = true; }) ];
  }).config;
  ddmBlockedMessages = map (item: item.message)
    (builtins.filter (item: !item.assertion) ddmBlocked.assertions);
  # The complete opt-in path: patched pin, private credentials, the bridge,
  # and one pinned enrollment. Fixture hashes/secrets only; never deploy.
  ddmOn = (onSystem.extendModules {
    modules = [ ({ ... }: {
      malli.mdm.declarativeManagement = {
        enable = true;
        sendHmacSopsFile = ../secrets/vista/deus_deploy_key; # fixture only
        recvHmacSopsFile = ../secrets/vista/malli_nix_deploy_key; # fixture only
      };
      malli.mdm.ddmBridge = {
        enable = true;
        identityMigrationConfirmed = true; # evaluation only
        credentialMigrationConfirmed = true; # evaluation only
        receiverConfigured = true; # evaluation only
        enrollmentID = "OFFLINE-TEST-ENROLLMENT-ID";
      };
    }) ];
  }).config;
  hasInfix = vista.pkgs.lib.hasInfix;
  nanoOff = off.virtualisation.oci-containers.containers.nanomdm;
  nanoPrepared = prepared.virtualisation.oci-containers.containers.nanomdm;
  nanoOn = on.virtualisation.oci-containers.containers.nanomdm;
  preparedADE = prepared.containers.headscale.config.services.deus.server.ade;
  onADE = on.containers.headscale.config.services.deus.server.ade;
in
assert !off.malli.mdm.privateCredentials.enable;
assert !off.malli.mdm.privateCredentials.prepare;
assert !off.malli.mdm.deusDedicatedIdentity.enable;
assert !off.malli.mdm.ddmBridge.enable;
assert builtins.elem "/run/secrets/rendered/nanomdm.env" nanoOff.environmentFiles;
assert !(builtins.elem "/var/lib/mdm/credentials:/run/mdm-credentials:ro" nanoOff.volumes);
assert !(builtins.hasAttr "/var/lib/deus-mdm-credentials" off.containers.headscale.bindMounts);
assert builtins.length blockedMessages >= 5;
assert nanoPrepared.image == nanoOff.image;
assert nanoPrepared.volumes == nanoOff.volumes;
assert nanoPrepared.environmentFiles == nanoOff.environmentFiles;
assert preparedADE.webhookSecretFile == "/var/lib/deus-tokens/private-mdm/nanomdm-api";
assert preparedADE.webhookHMACKeyFile == "/var/lib/deus-tokens/private-mdm/webhook-hmac";
assert prepared.containers.headscale.config.services.deus.server.stateDirMode == "0700";
assert prepared.systemd.services."container@headscale".serviceConfig.ExecStartPre != [ ];
assert builtins.filter (item: !item.assertion) prepared.assertions == [ ];
assert builtins.elem "/var/lib/mdm/credentials:/run/mdm-credentials:ro" nanoOn.volumes;
assert nanoOn.environmentFiles == [ ];
assert onADE.apiKeyFile == "/var/lib/deus-tokens/private-mdm/nanomdm-api";
assert onADE.webhookSecretFile == "/var/lib/deus-tokens/private-mdm/nanomdm-api";
assert onADE.webhookHMACKeyFile == "/var/lib/deus-tokens/private-mdm/webhook-hmac";
assert on.containers.headscale.bindMounts == off.containers.headscale.bindMounts;
assert !on.malli.mdm.ddmBridge.enable;
assert builtins.filter (item: !item.assertion) on.assertions == [ ];
assert builtins.elem
  "Private MDM cutover requires a separately deployed and verified receiver-first prepare generation."
  (map (item: item.message) (builtins.filter (item: !item.assertion) unverifiedPrepare.assertions));
assert builtins.elem
  "Legacy ADE webhook auth cannot be retired before HMAC-only NanoMDM traffic is independently verified."
  (map (item: item.message) (builtins.filter (item: !item.assertion) unverifiedRetirement.assertions));
assert verifiedRetirement.containers.headscale.config.services.deus.server.ade.webhookSecretFile == "";
assert verifiedRetirement.containers.headscale.config.services.deus.server.ade.webhookHMACKeyFile ==
  "/var/lib/deus-tokens/private-mdm/webhook-hmac";
assert builtins.filter (item: !item.assertion) verifiedRetirement.assertions == [ ];
# ── Declarative management ───────────────────────────────────────────────
assert !off.malli.mdm.declarativeManagement.enable;
assert off.malli.mdm.declarativeManagement.sendHmacSopsFile == null;
assert off.malli.mdm.declarativeManagement.recvHmacSopsFile == null;
assert !(builtins.hasAttr "nanomdm_dm_send_hmac_key" off.sops.secrets);
assert !on.malli.mdm.declarativeManagement.enable;
assert !off.containers.headscale.config.services.deus.server.ddm.enable;
assert !on.containers.headscale.config.services.deus.server.ddm.enable;
# -dm cannot be reached past any single missing prerequisite.
assert builtins.elem
  "Declarative management requires the endpoint-confined patched NanoMDM v0.9 pin; stock v0.9 resolves device-supplied -dm endpoints and must never be given -dm."
  ddmBlockedMessages;
assert builtins.elem
  "Declarative management requires malli.mdm.privateCredentials.enable; the DM HMAC key files are only staged and mounted on that path."
  ddmBlockedMessages;
assert builtins.elem
  "Declarative management requires separately encrypted DM send and receive HMAC secret files (malli.mdm.declarativeManagement.sendHmacSopsFile / recvHmacSopsFile)."
  ddmBlockedMessages;
assert builtins.elem
  "Declarative management requires malli.mdm.ddmBridge.enable; without the bridge nothing serves the -dm endpoint."
  ddmBlockedMessages;
assert ddmBlocked.virtualisation.oci-containers.containers.nanomdm == nanoOff;
# The complete path evaluates, stages both DM keys, creates exactly one new
# private directory, and pins the Deus listener to one enrollment.
assert builtins.filter (item: !item.assertion) ddmOn.assertions == [ ];
assert hasInfix "/run/secrets/nanomdm_dm_send_hmac_key"
  ddmOn.system.activationScripts.vista-mdm-stage-credentials.text;
assert hasInfix "/run/secrets/nanomdm_dm_recv_hmac_key"
  ddmOn.system.activationScripts.vista-mdm-stage-credentials.text;
assert ddmOn.sops.secrets.nanomdm_dm_send_hmac_key.mode == "0600";
assert ddmOn.sops.secrets.nanomdm_dm_recv_hmac_key.mode == "0600";
assert builtins.elem "d /var/lib/deus/ddm-private 0700 3999 3999 -"
  ddmOn.systemd.tmpfiles.rules;
assert ddmOn.containers.headscale.config.services.deus.server.ddm.enable;
assert ddmOn.containers.headscale.config.services.deus.server.ddm.enrollmentID
  == "OFFLINE-TEST-ENROLLMENT-ID";
assert ddmOn.containers.headscale.config.services.deus.server.ddm.socketPath
  == "/var/lib/deus/ddm-private/socket";
assert ddmOn.containers.headscale.config.services.deus.server.ddm.peerUID == 3999;
assert builtins.filter (item: !item.assertion)
  ddmOn.containers.headscale.config.assertions == [ ];
{
  defaultOff = true;
  missingPrerequisitesFailClosed = true;
  receiverFirstPreparationKeepsNanoMDMUnchanged = true;
  privateCutoverEvaluatesWithoutBridge = true;
  prepareAndRetirementAttestationsFailClosed = true;
  declarativeManagementDefaultOffAndFailsClosed = true;
  declarativeManagementCompletePathEvaluates = true;
  # Forces a full opt-in system evaluation, not just the option surface.
  declarativeManagementToplevel = ddmOn.system.build.toplevel.drvPath;
}
