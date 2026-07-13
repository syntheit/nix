{ config, ... }:

{
  # sops-nix — secrets decrypted at activation time to /run/secrets/.
  # vista's own age identity (derived from its SSH host key) is a recipient on
  # secrets/vista.yaml; see .sops.yaml. Edit the secret values with
  # `sops secrets/vista.yaml`.
  sops.defaultSopsFile = ../../secrets/vista.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # TubeArchivist credentials.
  sops.secrets.ta_password = { };
  sops.secrets.ta_elastic_password = { };

  # TubeArchivist env file — rendered from sops at boot, consumed by the
  # tubearchivist + archivist-es containers (see tubearchivist.nix). ELASTIC_PASSWORD
  # must match between the two, which is why it lives in one shared file.
  sops.templates."tubearchivist.env".content = ''
    TA_USERNAME=daniel
    TA_PASSWORD=${config.sops.placeholder.ta_password}
    ELASTIC_PASSWORD=${config.sops.placeholder.ta_elastic_password}
  '';
}
