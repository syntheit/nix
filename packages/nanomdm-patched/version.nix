# The version string of a patched NanoMDM build, from its source pin or from
# a row of hosts/vista/nanomdm-reviewed-source.nix: the vendored canary commit,
# then the reviewed Deus revision that carries it. It is compiled into the
# binary (/version, -version) and names the container image, so the running
# server says which reviewed source it is. One definition, shared by the
# package and the DDM bridge's image-tag check, so the two cannot drift.
{ nanomdmCommit, deusRev, ... }:
"0.9.0-patched-${builtins.substring 0 12 nanomdmCommit}-deus-${builtins.substring 0 12 deusRev}"
