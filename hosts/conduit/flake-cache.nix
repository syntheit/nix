# Conduit-hosted flake-input cache.
#
# Problem: Nix substituters do NOT serve flake INPUTS — flake inputs
# are fetched by `fetchTree` at eval time, which bypasses substituters
# entirely. That's why the existing m-1w6l-vm LAN cache
# (malli-nix/modules/vm-cache.nix) never helps with "darwin-rebuild hit
# GitHub for nixpkgs/home-manager/nix-darwin/deus/etc. and either got
# rate-limited or GitHub had a blip" — that cache only ever served
# already-fetched *build outputs*, never flake sources.
#
# Fix: if a flake input's exact store path is already valid in the
# LOCAL store, `fetchTree` short-circuits and never touches GitHub —
# even with `--refresh` (verified interactively against a real
# flake.lock). So instead of trying to intercept fetchTree (we can't —
# it doesn't consult substituters), we proactively pre-seed the Mac's
# local store with those exact paths before darwin-rebuild ever runs
# eval. Two pieces, both here:
#
#   1. harmonia — a Nix binary-cache server (services.harmonia)
#      exposing conduit's /nix/store over the tailnet, so `nix copy
#      --from http://conduit:<cachePort>` can pull an input's source
#      store path onto a Mac.
#   2. malli-flake-cache-archive.service/.timer — a periodic job that
#      runs `nix flake archive` against malli-nix (from conduit) to
#      fetch every locked flake input into *this* store from live
#      GitHub, then publishes the resulting store-path list as a
#      manifest the fleet can fetch over HTTP.
#
# The consumer is malli-deus's PreseedFlakeInputs bootstrap step
# (internal/bootstrap/steps/preseed.go): it fetches the manifest, then
# runs `nix copy --from http://conduit:<cachePort> --no-check-sigs
# <paths...>` immediately before DarwinRebuildFleet. That step is
# non-fatal by design — if this cache is unreachable or the manifest is
# missing, darwin-rebuild falls back to fetching inputs from GitHub
# directly, exactly as it did before any of this existed.
#
# --no-check-sigs on the Mac side means harmonia's signing key never
# has to be distributed to the fleet — the wireguard-encrypted tailnet
# is the trust boundary (same reasoning the plaintext git:// mirror
# above already relies on). harmonia still requires a signing key to
# run at all, so one is generated on first boot and kept local to
# conduit; its public half lives at signingKeyDir/signing-key.pub if a
# trusted-key push is ever wanted later.
{ config, pkgs, lib, ... }:

let
  cachePort = 7080; # harmonia binary-cache HTTP API
  manifestPort = 7081; # tiny static server for the manifest file
  archiveStateDir = "/var/lib/malli-flake-cache";
  manifestDir = "/var/lib/malli-manifest";
  signingKeyDir = "/var/lib/harmonia";
in
{
  # ── harmonia binary-cache server ──────────────────────────
  services.harmonia.cache = {
    enable = true;
    signKeyPaths = [ "${signingKeyDir}/signing-key.sec" ];
    settings.bind = "0.0.0.0:${toString cachePort}";
  };

  # harmonia.nix's upstream module only wires `after/requires =
  # [ "harmonia.socket" ]`; make sure the signing key exists first too,
  # since LoadCredential reads it at service start.
  systemd.services.harmonia = {
    after = [ "malli-harmonia-signing-key.service" ];
    wants = [ "malli-harmonia-signing-key.service" ];
  };

  systemd.services.malli-harmonia-signing-key = {
    description = "Generate harmonia's binary-cache signing key (first boot only)";
    before = [ "harmonia.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -e
      mkdir -p ${signingKeyDir}
      if [ ! -f ${signingKeyDir}/signing-key.sec ]; then
        ${config.nix.package}/bin/nix-store --generate-binary-cache-key \
          conduit-flake-cache-1 \
          ${signingKeyDir}/signing-key.sec \
          ${signingKeyDir}/signing-key.pub
        chmod 600 ${signingKeyDir}/signing-key.sec
        chmod 644 ${signingKeyDir}/signing-key.pub
      fi
    '';
  };

  # Dedicated, unprivileged host-level user for the archive job. Note
  # this is NOT the same `fleet` as headscale.nix's — that one only
  # exists inside the headscale NixOS *container*; this job runs on the
  # host (where harmonia and /nix/store live directly), so it needs its
  # own host-level identity.
  users.users.malli-flake-cache = {
    isSystemUser = true;
    group = "malli-flake-cache";
    description = "Runs the malli-nix flake-input archive job";
  };
  users.groups.malli-flake-cache = { };

  # ── flake-input archive + manifest job ────────────────────
  # The ONE place that talks to live GitHub for the fleet's flake
  # inputs — off the hands-free bootstrap path, retryable, and never
  # blocking: a GitHub blip here just means the timer retries next
  # cycle.
  systemd.services.malli-flake-cache-archive = {
    description = "Archive malli-nix's flake inputs into the local store + publish manifest";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.git config.nix.package pkgs.jq pkgs.coreutils ];
    # The system user's home is /var/empty (unwritable), but nix's git
    # fetcher + flake eval need a writable $HOME/.cache/nix. Point HOME +
    # XDG_CACHE_HOME at the (user-owned) state dir.
    environment = {
      HOME = archiveStateDir;
      XDG_CACHE_HOME = "${archiveStateDir}/.cache";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "malli-flake-cache";
      Group = "malli-flake-cache";
    };
    script = ''
      set -euo pipefail
      mkdir -p ${archiveStateDir} ${manifestDir}
      src=${archiveStateDir}/malli-nix
      rm -rf "$src"

      # Pull from the LOCAL mirror, not GitHub directly — the
      # malli-nix-mirror timer inside the headscale container (see
      # headscale.nix) already keeps /var/lib/git-mirror/malli-nix.git
      # fresh off GitHub every 5 minutes. Reaching it via
      # git://127.0.0.1 works because that container runs with host
      # networking (privateNetwork = false in headscale.nix), so its
      # gitDaemon on :9418 binds the host's real interfaces including
      # loopback.
      echo "cloning local malli-nix mirror..."
      git clone --depth 1 git://127.0.0.1/malli-nix.git "$src"

      # `nix flake archive` recursively fetches every flake input (and
      # every one of *their* inputs) into the local store. With --json
      # it prints a tree of the resulting store paths instead of just
      # doing the fetch silently — this is the only command in this
      # whole job that talks to live GitHub (nixpkgs, home-manager,
      # nix-darwin, disko, sops-nix, ... — public repos, fetched over
      # https, no credentials needed). The flake's own "deus" input
      # (git://conduit/malli-deus.git) is already conduit-local; the
      # networking.hosts entry below pins "conduit" to 127.0.0.1 on
      # this host so that resolves without depending on MagicDNS
      # self-resolution.
      echo "archiving flake inputs (talks to GitHub)..."
      archive_json=$(nix --extra-experimental-features 'nix-command flakes' \
        flake archive --json "$src")

      # Flatten the recursive {"path":..., "inputs": {...}} tree into a
      # newline-separated list of every store path in it (including the
      # malli-nix source tree itself — harmless to include, harmless to
      # never use).
      echo "$archive_json" | jq -r '[.. | .path? // empty] | unique | .[]' \
        > ${manifestDir}/manifest.txt.new
      mv ${manifestDir}/manifest.txt.new ${manifestDir}/manifest.txt
      echo "wrote $(wc -l < ${manifestDir}/manifest.txt) store paths to manifest"

      # `nix flake archive` only fetches into the store — it does NOT
      # register a GC root, so without this these paths are "dead" the
      # moment they land (verified: nix-store --gc --print-dead flags a
      # freshly-archived path with zero roots). conduit runs weekly
      # automatic GC (see default.nix); without a root, any GC sweep
      # between archive runs could collect a path this manifest still
      # advertises, and the fleet's `nix copy --from` would 404 on it
      # until the next 20-min cycle re-fetches it. --add-root --indirect
      # is the standard non-root-safe way to pin a store path (the
      # daemon does the actual privileged bookkeeping; this service's
      # own user only needs write access to the symlink's directory).
      # Rebuilt from
      # scratch every run so paths that drop out of the lock eventually
      # become collectible again instead of pinning forever.
      rm -rf ${archiveStateDir}/roots
      mkdir -p ${archiveStateDir}/roots
      i=0
      while IFS= read -r p; do
        i=$((i + 1))
        nix-store --add-root "${archiveStateDir}/roots/$i" --indirect -r "$p"
      done < ${manifestDir}/manifest.txt
      echo "rooted $i store paths against GC"
    '';
  };

  systemd.timers.malli-flake-cache-archive = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "20m";
    };
  };

  # conduit's own copy of malli-nix's flake.lock resolves the "deus"
  # input to git://conduit/malli-deus.git. Whether "conduit" resolves
  # to *itself* via headscale's MagicDNS isn't a given (self-lookups
  # aren't guaranteed the same way a peer-to-peer lookup is), so pin it
  # explicitly here — the exact same fix deus's pinConduitHost applies
  # on every Mac, just aimed at 127.0.0.1 since this really is conduit.
  networking.hosts."127.0.0.1" = [ "conduit" ];

  # ── manifest static file server ───────────────────────────
  # harmonia only speaks the Nix binary-cache protocol (narinfo/nar),
  # not arbitrary static files, so the manifest gets its own tiny
  # server. python3's http.server is plenty for a KB-sized text file
  # hit a few times an hour by the fleet.
  systemd.services.malli-manifest-http = {
    description = "Serve the flake-input cache manifest";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString manifestPort} --directory ${manifestDir} --bind 0.0.0.0";
      Restart = "always";
      RestartSec = "5s";
      DynamicUser = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d ${archiveStateDir} 0755 malli-flake-cache malli-flake-cache -"
    "d ${manifestDir} 0755 malli-flake-cache malli-flake-cache -"
  ];

  # harmonia and the manifest server both bind 0.0.0.0, but conduit's
  # host firewall (default.nix) only trusts wg0 + tailscale0 — these
  # ports are not internet-exposed. Matches the existing pattern right
  # below for the git-mirror/deus-server ports.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cachePort manifestPort ];
}
