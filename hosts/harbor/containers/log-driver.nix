{ lib, ... }:

# Every oci-container logs through Docker's json-file driver (rotated by the
# daemon's log-opts in ./default.nix), not oci-containers' default "journald".
# With journald, each line was stored twice: once by the log driver and once
# by the attached `docker run` in the docker-<name> unit (about half the
# journal on 2026-11-01). The unit's copy remains, and `docker logs` works.
{
  options.virtualisation.oci-containers.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.log-driver = lib.mkDefault "json-file";
      }
    );
  };
}
