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
  #
  # reviewedSourcePins is set here because the shipped allowlist in
  # hosts/vista/nanomdm-reviewed-source.nix is EMPTY — no revision of the
  # endpoint-confined fork has been published or reviewed yet — so without
  # this the opt-in path correctly refuses to evaluate at all. The fixture
  # allowlists exactly the fixture pin and nothing else.
  ddmOnSystem = onSystem.extendModules {
    modules = [ ({ ... }: {
      malli.mdm.declarativeManagement = {
        enable = true;
        sendHmacSopsFile = ../secrets/vista/deus_deploy_key; # fixture only
        recvHmacSopsFile = ../secrets/vista/malli_nix_deploy_key; # fixture only
        receiptHmacSopsFile = ../secrets/vista/deus_fleet_age_key; # fixture only
        reviewedSourcePins = [{
          inherit (pin) owner repo rev; # evaluation fixture; never deploy
        }];
      };
      malli.mdm.ddmBridge = {
        enable = true;
        identityMigrationConfirmed = true; # evaluation only
        credentialMigrationConfirmed = true; # evaluation only
        receiverConfigured = true; # evaluation only
        enrollmentID = "OFFLINE-TEST-ENROLLMENT-ID";
      };
    }) ];
  };
  ddmOn = ddmOnSystem.config;
  # ── The reviewer's construction: a well-formed pin naming stock upstream ──
  # Every other prerequisite is satisfied, so this is exactly the "all
  # assertions pass" configuration that used to hand -dm to the unpatched
  # v0.9 build. It must now be refused twice over: once for not being on the
  # reviewed allowlist, and once — even if an operator adds it to the
  # allowlist — for naming an upstream owner at all.
  stockUpstreamPin = {
    owner = "micromdm";
    repo = "nanomdm";
    rev = "1111111111111111111111111111111111111111";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  stockUpstream = (ddmOnSystem.extendModules {
    modules = [ ({ lib, ... }: {
      malli.mdm.nanomdmPatchedSourcePin = lib.mkForce stockUpstreamPin;
    }) ];
  }).config;
  stockUpstreamMessages = map (item: item.message)
    (builtins.filter (item: !item.assertion) stockUpstream.assertions);
  stockUpstreamAllowlisted = (ddmOnSystem.extendModules {
    modules = [ ({ lib, ... }: {
      malli.mdm.nanomdmPatchedSourcePin = lib.mkForce stockUpstreamPin;
      malli.mdm.declarativeManagement.reviewedSourcePins = lib.mkForce [{
        inherit (stockUpstreamPin) owner repo rev;
      }];
    }) ];
  }).config;
  stockUpstreamAllowlistedMessages = map (item: item.message)
    (builtins.filter (item: !item.assertion) stockUpstreamAllowlisted.assertions);
  # Two of the three DM keys is not "receipts off", it is a listener that
  # never binds, so the trio is refused as a unit.
  ddmMissingReceiptKey = (ddmOnSystem.extendModules {
    modules = [ ({ lib, ... }: {
      malli.mdm.declarativeManagement.receiptHmacSopsFile = lib.mkForce null;
    }) ];
  }).config;
  ddmMissingReceiptKeyMessages = map (item: item.message)
    (builtins.filter (item: !item.assertion) ddmMissingReceiptKey.assertions);
  lib = vista.pkgs.lib;
  hasInfix = lib.hasInfix;
  # ── Credential staging vs. what Deus actually asks systemd for ───────────
  # The listener starts only if every BARE LoadCredential name resolves in the
  # credstore, so compare the two sets rather than eyeballing option values.
  ddmContainer = ddmOn.containers.headscale.config;
  deusCredentials =
    ddmContainer.systemd.services.deus-server.serviceConfig.LoadCredential;
  bareCredentials = builtins.filter
    (name: builtins.match "[^:]+" name != null) deusCredentials;
  tmpfilesRules = ddmContainer.systemd.tmpfiles.rules;
  credstoreName = pattern: rule: builtins.head (builtins.match pattern rule);
  stagedCredentials = map (credstoreName "C\\+ /run/credstore/([^ ]+).*")
    (builtins.filter (lib.hasPrefix "C+ /run/credstore/") tmpfilesRules);
  removedCredentials = map (credstoreName "r /run/credstore/([^ ]+)")
    (builtins.filter (lib.hasPrefix "r /run/credstore/") tmpfilesRules);
  # tmpfiles' C+ does not overwrite an existing destination, so a rotated key
  # would silently keep serving the boot-time copy. Each copy must be directly
  # preceded by the removal of the same path.
  removalPrecedesEveryCopy = builtins.all (index:
    let rule = builtins.elemAt tmpfilesRules index; in
    !(lib.hasPrefix "C+ /run/credstore/" rule)
    || (index > 0 && builtins.elemAt tmpfilesRules (index - 1)
      == "r ${credstoreName "C\\+ (/run/credstore/[^ ]+).*" rule}"))
    (lib.range 0 (builtins.length tmpfilesRules - 1));
  # The -dm prefix and the bridge's listen tuple are built from one host and
  # one port. Take the address apart from the endpoint side and require the
  # bridge to be listening on exactly it, so changing either alone fails.
  endpointAddress = builtins.match "http://([0-9.]+):([0-9]+)/"
    ddmOn.malli.mdm.declarativeManagement.endpointURL;
  endpointListensOnBridge = endpointAddress != null && hasInfix
    ''LISTEN = ("${builtins.elemAt endpointAddress 0}", ${builtins.elemAt endpointAddress 1})''
    (builtins.readFile ../packages/nanomdm-ddm-bridge.py);
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
  "Declarative management requires three separately encrypted DM HMAC secret files (malli.mdm.declarativeManagement.sendHmacSopsFile / recvHmacSopsFile / receiptHmacSopsFile); Deus disables its whole private listener when the receipt key file is absent."
  ddmBlockedMessages;
assert builtins.elem
  "Declarative management requires malli.mdm.ddmBridge.enable; without the bridge nothing serves the -dm endpoint."
  ddmBlockedMessages;
assert ddmBlocked.virtualisation.oci-containers.containers.nanomdm == nanoOff;
# ── A pin is not a review: stock upstream must be refused ────────────────
# The shipped allowlist is empty, so no pin at all can reach -dm today.
assert off.malli.mdm.declarativeManagement.reviewedSourcePins == [ ];
# A well-formed pin naming upstream, with every other prerequisite met, is
# refused for not being reviewed…
assert builtins.elem
  "The patched NanoMDM pin is not on the reviewed declarative-management allowlist; add the audited owner/repo/revision to hosts/vista/nanomdm-reviewed-source.nix only after reading its endpoint confinement and running the canary."
  stockUpstreamMessages;
# …and refused again, by name, for being upstream at all — even after an
# operator has written it into the allowlist.
assert builtins.elem
  "Upstream NanoMDM (micromdm/jessepeterson) is the unpatched build whose -dm resolves device-supplied endpoints into a request-forgery proxy; it can never be a declarative-management source, allowlisted or not."
  stockUpstreamAllowlistedMessages;
# The bridge's own gate must depend on the allowlist, not on a name it
# derives from the same pin it is meant to be checking.
assert builtins.elem
  "DDM bridge requires a NanoMDM source pin on the reviewed declarative-management allowlist in hosts/vista/nanomdm-reviewed-source.nix; an arbitrary v0.9 pin is the unpatched, request-forgery build."
  stockUpstreamMessages;
assert builtins.elem
  "DDM bridge requires the configured NanoMDM image tag to be one built from a reviewed, endpoint-confined revision (hosts/vista/nanomdm-reviewed-source.nix)."
  stockUpstreamMessages;
# The complete path evaluates, stages all three DM keys, creates exactly one
# new private directory, and pins the Deus listener to one enrollment.
assert builtins.filter (item: !item.assertion) ddmOn.assertions == [ ];
assert hasInfix "/run/secrets/nanomdm_dm_send_hmac_key"
  ddmOn.system.activationScripts.vista-mdm-stage-credentials.text;
assert hasInfix "/run/secrets/nanomdm_dm_recv_hmac_key"
  ddmOn.system.activationScripts.vista-mdm-stage-credentials.text;
assert hasInfix "/run/secrets/nanomdm_dm_receipt_hmac_key"
  ddmOn.system.activationScripts.vista-mdm-stage-credentials.text;
assert ddmOn.sops.secrets.nanomdm_dm_send_hmac_key.mode == "0600";
assert ddmOn.sops.secrets.nanomdm_dm_recv_hmac_key.mode == "0600";
assert ddmOn.sops.secrets.nanomdm_dm_receipt_hmac_key.mode == "0600";
assert builtins.elem "d /var/lib/deus/ddm-private 0700 3999 3999 -"
  ddmOn.systemd.tmpfiles.rules;
# ── Every credential Deus asks systemd for must actually be staged ───────
# Deus emits -ddm-receipt-key-file unconditionally with DDM on, and a name
# it cannot resolve takes the WHOLE private listener down, so equality of
# the two sets — not the presence of the two we happened to think of — is
# what says the listener can start.
assert builtins.elem
  "Declarative management requires three separately encrypted DM HMAC secret files (malli.mdm.declarativeManagement.sendHmacSopsFile / recvHmacSopsFile / receiptHmacSopsFile); Deus disables its whole private listener when the receipt key file is absent."
  ddmMissingReceiptKeyMessages;
assert bareCredentials == [ "ddm-request-hmac" "ddm-response-hmac" "ddm-receipt-hmac" ];
assert builtins.all (name: builtins.elem name stagedCredentials) bareCredentials;
assert builtins.all (name: builtins.elem name bareCredentials) stagedCredentials;
# A rotated key must not silently keep serving the boot-time copy.
assert removedCredentials == stagedCredentials;
assert removalPrecedesEveryCopy;
# ── The -dm endpoint and the bridge listener are one address ─────────────
assert endpointListensOnBridge;
# ── The reload must not outrun the staging it copies from ────────────────
assert off.system.activationScripts.reload-headscale-container.deps == [ "etc" ];
assert ddmOn.system.activationScripts.reload-headscale-container.deps
  == [ "etc" "vista-mdm-stage-credentials" ];
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
  stockUpstreamPinIsRefusedByTheReviewedAllowlist = true;
  everyDeusDDMCredentialIsStagedAndRefreshedOnRotation = true;
  dmEndpointAndBridgeListenerCannotDrift = true;
  containerReloadWaitsForCredentialStaging = true;
  # Forces a full opt-in system evaluation, not just the option surface.
  declarativeManagementToplevel = ddmOn.system.build.toplevel.drvPath;
}
