# hosts/vista/mdm-5fro.nix: sequence A switches for the 5fro canary.
# Each step uncomments its own block with sed; see ~/malli-5fro-m2-runbook.md.
{ ... }: {
  malli.mdm.nanomdmPatchedSourcePin = {
    deusRev = "af0140b4597a2e77bab3327adf75be85e128c900";
    nanomdmCommit = "3c52ba4a031c6d2035cea0722a47c598318fc59d";
    hash = "sha256-lhhXPgBp7SmdMCQc1c9/3ZBmrAbElvdXDtEWN68BP/Y=";
    vendorHash = "sha256-W49woVx8MjNZsfGHPudYReTRggnjfZ4f3VKCwgqaaV0=";
  };
  malli.mdm.deusDedicatedIdentity.enable = true;
  malli.mdm.deusDedicatedIdentity.migrationConfirmed = true;
  malli.mdm.privateCredentials.prepare = true;
  malli.mdm.privateCredentials.receiverVerified = true;
  malli.mdm.privateCredentials.hmacSopsFile = ../../secrets/vista/nanomdm_webhook_hmac;
  malli.mdm.privateCredentials.nanodepSopsFile = ../../secrets/vista/nanodep_api;
  #S5b malli.mdm.privateCredentials.enable = true;
  #S5b malli.mdm.privateCredentials.apiKeyVerified = true;
  #S5b malli.mdm.privateCredentials.prepareDeployedAndVerified = true;
  #S6 malli.mdm.declarativeManagement.enable = true;
  #S6 malli.mdm.declarativeManagement.sendHmacSopsFile = ../../secrets/vista/nanomdm_dm_send_hmac;
  #S6 malli.mdm.declarativeManagement.recvHmacSopsFile = ../../secrets/vista/nanomdm_dm_recv_hmac;
  #S6 malli.mdm.declarativeManagement.receiptHmacSopsFile = ../../secrets/vista/deus_ddm_receipt_hmac;
  #S6 malli.mdm.ddmBridge.enable = true;
  #S6 malli.mdm.ddmBridge.enrollmentID = "88A36832-E552-5F84-9040-B43CEABEA35A";
  #S6 malli.mdm.ddmBridge.identityMigrationConfirmed = true;
  #S6 malli.mdm.ddmBridge.receiverConfigured = true;
  #S6 malli.mdm.ddmBridge.credentialMigrationConfirmed = true;
}
