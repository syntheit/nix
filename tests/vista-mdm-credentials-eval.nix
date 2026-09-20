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
{
  defaultOff = true;
  missingPrerequisitesFailClosed = true;
  receiverFirstPreparationKeepsNanoMDMUnchanged = true;
  privateCutoverEvaluatesWithoutBridge = true;
  prepareAndRetirementAttestationsFailClosed = true;
}
