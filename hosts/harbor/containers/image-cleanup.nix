{
  config,
  lib,
  pkgs,
  ...
}:

# Weekly removal of Docker images nothing uses, with explicit protections.
# Also removes dangling images (replaces autoPrune, which ran `docker system
# prune` and deleted unused networks too). `prune --all`
# can't be used because it would also delete rollback images and the images
# of configured containers that happen to be stopped (oci-containers runs
# with --rm, so a stopped service has no container referencing its image).
#
# An image is removed only if ALL of these hold:
#   - no container (running or stopped) uses it
#   - no tag matches keepPattern (rollback images; malli local builds, which
#     can't be re-pulled, until Daniel decides they can go)
#   - its repository isn't one the NixOS config runs (any tag), nor in
#     extraProtectedRepos (images run by scripts via `docker run --rm`)
#   - it was tagged/pulled locally more than 7 days ago (Metadata.LastTagTime;
#     local builds have Created=1970, so Created can't be used)
#
# Review first: `sudo docker-image-cleanup --dry-run`.
let
  # Repository part of an image reference, normalized the way RepoTags shows it.
  repoOf =
    image:
    let
      noDigest = builtins.head (lib.splitString "@" image);
      parts = lib.splitString "/" noDigest;
      last = lib.last parts;
      lastNoTag = builtins.head (lib.splitString ":" last);
      repo = lib.concatStringsSep "/" (lib.init parts ++ [ lastNoTag ]);
    in
    lib.removePrefix "library/" (lib.removePrefix "docker.io/" repo);

  keepPattern = "rollback|malli|agent-orchestrator";

  # Run by scripts with `docker run --rm`, so no container keeps them "in use".
  extraProtectedRepos = [
    "ghcr.io/recyclarr/recyclarr" # containers/recyclarr.nix, daily 04:30
  ];

  protectedRepos = lib.unique (
    extraProtectedRepos
    ++ lib.mapAttrsToList (_: c: repoOf c.image) config.virtualisation.oci-containers.containers
  );

  cleanup = pkgs.writeShellApplication {
    name = "docker-image-cleanup";
    runtimeInputs = [
      pkgs.docker
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
      dry=0
      [ "''${1:-}" = "--dry-run" ] && dry=1
      protected=${pkgs.writeText "protected-repos" (lib.concatStringsSep "\n" protectedRepos + "\n")}
      cutoff=$(date -d '7 days ago' +%s)
      used=$(docker ps -aq | xargs -r docker inspect -f '{{.Image}}' | sort -u)

      norm() { sed -E 's#^docker\.io/##; s#^library/##; s#:[^/:]*$##'; }

      if [ "$dry" = 1 ]; then
        echo "dangling images: $(docker images -qf dangling=true | wc -l) (would be pruned)"
      else
        docker image prune -f
      fi

      removed=0
      while read -r id; do
        grep -qxF "$id" <<<"$used" && continue
        tags=$(docker image inspect -f '{{join .RepoTags " "}}' "$id")
        [ -z "$tags" ] && continue # dangling: docker-prune handles these
        grep -qE '${keepPattern}' <<<"$tags" && continue
        keep=0
        for t in $tags; do
          grep -qxF "$(norm <<<"$t")" "$protected" && keep=1
        done
        [ "$keep" = 1 ] && continue
        last=$(docker image inspect -f '{{.Metadata.LastTagTime}}' "$id")
        ts=$(date -d "$last" +%s 2>/dev/null || echo 0)
        [ "$ts" -gt "$cutoff" ] && continue
        if [ "$dry" = 1 ]; then
          echo "would remove: $tags (last tagged $last)"
        else
          echo "removing: $tags"
          docker rmi "$id" >/dev/null || echo "  skipped (in use or has dependents)"
        fi
        removed=$((removed + 1))
      done < <(docker image ls -q --no-trunc | sort -u)
      echo "$removed image(s) $([ "$dry" = 1 ] && echo 'would be ')removed"
    '';
  };
in
{
  environment.systemPackages = [ cleanup ];

  systemd.services.docker-image-cleanup = {
    description = "Remove unused Docker images (keeps rollback and configured images)";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe cleanup;
    };
  };
  systemd.timers.docker-image-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon 00:30";
      # No catch-up run at boot: skipping a week is harmless, and boot is when
      # stacks are half-started.
      Persistent = false;
    };
  };
}
