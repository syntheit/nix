# Headscale — open-source Tailscale coordination server.
# Runs inside a NixOS container (systemd-nspawn) for isolation.
# Coworkers SSH into the container to manage the fleet, without
# access to the host system.
#
# Migration: headscale data is bind-mounted from the host at
# /var/lib/headscale. Backup at /var/backups/headscale.
#
# Usage (from anywhere):
#   ssh fleet@headscale.matv.io -p 2222    # SSH into container
#   headscale nodes list                    # view fleet
#   ssh tars@m-1w6l                         # SSH to Mac Mini (via tailnet)
#   ssh lima@m-1w6l-vm                      # SSH to VM (via tailnet)

{ pkgs, lib, config, inputs, vars, ... }:

let
  headscale-ui-src = pkgs.fetchzip {
    url = "https://github.com/gurucomputing/headscale-ui/releases/download/2025.01.20/headscale-ui.zip";
    hash = "sha256-eMT3/UsTYkiJFzoWlNPOM6hgbyGoBbPi3cs/u71KJ0c=";
    stripRoot = false;
  };
  headscale-ui = headscale-ui-src;

  # ── ADE bootstrap-creds vend + trust-profile push (gated) ──────────
  # Both artifacts are operator-provisioned one-time secrets/files that
  # aren't in the repo yet, so every dependent bit is gated on their
  # presence. This keeps `nixos-rebuild build .#conduit` green and — more
  # importantly — keeps deus-server from crash-looping on a missing file
  # (it os.Exit(1)s if -ade-age-key-file / -ade-trust-profile-file point
  # at a nonexistent path). Drop the files in and the wiring activates.
  #
  #   secrets/conduit/deus_fleet_age_key
  #     The fleet sops age PRIVATE key (age13gxgn… pub) vended to a
  #     bootstrapping Mac so its first darwin-rebuild can decrypt fleet
  #     secrets. Create (from the malli-nix repo root, which holds the
  #     key) with:
  #       sops --encrypt --input-type binary --output-type binary \
  #         /path/to/fleet-age-key.txt \
  #         > ~/nix/secrets/conduit/deus_fleet_age_key
  #     (.sops.yaml already routes secrets/conduit/* to conduit+daniel.)
  #
  #   hosts/conduit/malli-installer-trust.mobileconfig
  #     The com.apple.security.pkcs1 profile emitted by
  #       nix run '.#gen-installer-identity' -- ./out   (in malli-nix)
  #     alongside installer.p12 (used to sign the pkg). Commit the
  #     .mobileconfig here; keep installer.p12 out of the repo.
  fleetAgeKeyEnc   = ../../secrets/vista/deus_fleet_age_key;
  haveFleetAgeKey  = builtins.pathExists fleetAgeKeyEnc;
  trustProfile     = ./malli-installer-trust.mobileconfig;
  haveTrustProfile = builtins.pathExists trustProfile;
  # Fleet config profiles (fda/PPPC, gatekeeper, restrictions, …) built
  # from malli-nix/profiles and copied here; pushed via MDM after the trust
  # profile so a Mac has Full Disk Access etc. before Phase B runs.
  configProfiles   = ./profiles;
  haveProfiles     = builtins.pathExists configProfiles;
in
{
  systemd.tmpfiles.rules = [
    # Headscale state (db.sqlite) — bind-mounted into the nspawn. Must exist on
    # the host before the container starts. On conduit this pre-existed; on a
    # fresh vista, create it (the container's headscale StateDirectory takes
    # ownership on first start). The migrated DB is restored here at cutover.
    "d /var/lib/headscale 0750 root root -"
    # 0755 because the container's deus user (the only resident that
    # writes here) needs to traverse + read its own state files —
    # roles.json, deus.db, work tree. Previously 0750 root:root, which
    # silently 500'd every TUI request with "permission denied: open
    # /var/lib/deus/roles.json" the first time it was queried.
    "d /var/lib/deus 0755 root root -"
    # 0755 so the container's deus user can traverse to the world-readable token files inside.
    "d /var/lib/deus-tokens 0755 root root -"
    # 0750 — keys are root-only on the host; the container re-permissions for fleet/deus user.
    "d /var/lib/deus-keys 0750 root root -"
    # Granter master credentials. World-readable inside the container —
    # the only resident is the deus user and we want the fewest permission
    # gymnastics possible. The host-side directory is root-owned 0755 so
    # the container can traverse but unprivileged users on the host can't
    # read the files (the file mode itself is 0444).
    "d /var/lib/deus-granter 0755 root root -"
    # Hosting dir for the signed ADE bootstrap pkg, served publicly by
    # Caddy at bootstrap.matv.io/pkg/* (see the vhost below). Daniel scp's
    # the nix-built + signed pkg here.
    "d /var/lib/malli-bootstrap 0755 root root -"
  ];

  # Sops renders to /run/secrets, a host-only tmpfs the container can't
  # follow into. Stage actual file contents into bind-mounted paths so
  # the container reads real files, not dangling symlinks.
  # mkdir here too because activation runs before systemd.tmpfiles
  # recreates dirs on first deploy.
  system.activationScripts.deus-stage = {
    deps = [ "setupSecrets" ];
    text = ''
      ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/deus-tokens
      ${pkgs.coreutils}/bin/install -d -m 0750 /var/lib/deus-keys
      ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/deus-granter
      ${pkgs.coreutils}/bin/install -m 0444 /run/secrets/deus_operator_token /var/lib/deus-tokens/operator-token
      ${pkgs.coreutils}/bin/install -m 0444 /run/secrets/deus_agent_token    /var/lib/deus-tokens/agent-token
      ${pkgs.coreutils}/bin/install -m 0444 /run/secrets/deus_service_token  /var/lib/deus-tokens/service-token
      ${pkgs.coreutils}/bin/install -m 0400 /run/secrets/deus_deploy_key     /var/lib/deus-keys/deploy-malli-deus
      ${pkgs.coreutils}/bin/install -m 0400 /run/secrets/malli_nix_deploy_key /var/lib/deus-keys/deploy-malli-nix
      # Granter creds — best-effort install so half-configured deploys
      # leave the granter disabled rather than failing activation.
      stage_optional() {
        [ -f "$1" ] && ${pkgs.coreutils}/bin/install -m "$3" "$1" "$2" || true
      }
      stage_optional /run/secrets/cloudflare_api_token      /var/lib/deus-granter/cloudflare-token   0444
      stage_optional /run/secrets/cloudflare_account_id     /var/lib/deus-granter/cf-account-id      0444
      stage_optional /run/secrets/cloudflare_zone_id        /var/lib/deus-granter/cf-zone-id         0444
      stage_optional /run/secrets/deus_malli_nix_write_key  /var/lib/deus-keys/malli-nix-write       0400
      stage_optional /run/secrets/deus_github_app_key       /var/lib/deus-keys/github-app-key        0400
      # nanomdm API key (ADE enqueue auth + webhook ?token= secret).
      # Best-effort: until it's added to secrets/conduit.yaml the file is
      # absent and deus-server leaves the ADE orchestrator disabled.
      stage_optional /run/secrets/nanomdm_api               /var/lib/deus-tokens/nanomdm-api         0444
      # ADE bootstrap-creds vend: the fleet sops age key deus-server
      # hands a bootstrapping Mac. Best-effort — absent until the sops
      # secret is added (see the gating note at the top of this file).
      ${lib.optionalString haveFleetAgeKey ''
        stage_optional /run/secrets/deus_fleet_age_key      /var/lib/deus-tokens/fleet-age-key       0444
      ''}
      # Installer-trust profile pushed via MDM before the bootstrap pkg.
      # Not a secret (public cert) — copied straight from the repo.
      ${lib.optionalString haveTrustProfile ''
        ${pkgs.coreutils}/bin/install -m 0444 ${trustProfile} /var/lib/deus-tokens/installer-trust.mobileconfig
      ''}
      # Fleet config profiles pushed after the trust profile (FDA etc.).
      ${lib.optionalString haveProfiles ''
        ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/deus-tokens/profiles
        ${pkgs.coreutils}/bin/install -m 0444 ${configProfiles}/*.mobileconfig /var/lib/deus-tokens/profiles/
      ''}
    '';
  };

  # ── Headscale container ────────────────────────────────────
  containers.headscale = {
    autoStart = true;

    # Don't bounce the container on every host nixos-rebuild. Without
    # this, any change inside the container's system closure (a deus
    # binary version bump, a new systemd unit, a sops template tweak)
    # forces the host to do `systemctl stop && start
    # container@headscale.service`. That stop→start has an unfixed
    # upstream race (nixpkgs#80169) where the new nspawn instance
    # spawns before the previous one's machined record / mounts are
    # released — first deploy fails with exit code 4, second deploy
    # succeeds because nothing changed and the unit came up via
    # Restart=on-failure. Even when the bounce succeeds, deus-server
    # dies mid-flight and 38+ agents have to reconnect, which spikes
    # heartbeat-timeout cascades into the launchd EX_CONFIG penalty
    # box on the Mac side.
    #
    # Inner changes still apply on every deploy via the activation
    # script below: it compares the freshly-built closure path to
    # what's currently running inside the container and, on mismatch,
    # runs `systemctl reload container@headscale.service`. The unit's
    # ExecReload does `nixos-container run -- switch-to-configuration
    # test` inside the running container — restarts only inner
    # services whose definitions changed, leaves the nspawn process
    # untouched.
    #
    # Full bounces become operator-initiated (`sudo systemctl restart
    # container@headscale`) for the rare cases where a kernel or
    # nspawn-level setting actually changes.
    restartIfChanged = false;

    # Private networking so the nspawn is a SELF-CONTAINED unit: it runs its
    # OWN tailscaled (joining the malli tailnet via its own local headscale),
    # completely isolated from vista's host tailscale (which stays on the
    # personal/syntheit tailnet). deus reaches the Macs over the container's
    # tailscale exactly as it did via conduit's host tailscale before.
    #
    # External reach is unchanged from the fleet's point of view: conduit
    # forwards Caddy(:8085/:8086) + socat(:8086/:9418/:5000/:5001) + public
    # ssh(:2222) to vista, and forwardPorts below DNATs vista→container.
    privateNetwork = true;
    hostAddress = "10.100.1.1";
    localAddress = "10.100.1.2";
    enableTun = true; # /dev/net/tun for the container's own tailscaled
    # NB: nixos-container `forwardPorts` doesn't work here — like the veth, its
    # DNAT rules never get installed on this NetworkManager host. Ports are
    # exposed instead by the explicit DNAT in networking.firewall.extraCommands
    # (host side) → the container at 10.100.1.2.

    # Bind-mount headscale state from the host so data persists
    # across container rebuilds and is easy to back up.
    bindMounts = {
      "/var/lib/headscale" = {
        hostPath = "/var/lib/headscale";
        isReadOnly = false;
      };
      "/var/lib/deus" = {
        hostPath = "/var/lib/deus";
        isReadOnly = false;
      };
      "/var/lib/deus-tokens" = {
        hostPath = "/var/lib/deus-tokens";
        isReadOnly = true;
      };
      "/etc/deus-keys" = {
        hostPath = "/var/lib/deus-keys";
        isReadOnly = true;
      };
      "/etc/deus-granter" = {
        hostPath = "/var/lib/deus-granter";
        isReadOnly = true;
      };
      # Signed ADE bootstrap pkg + payload, served read-only by the
      # in-container Caddy on :8088 (bootstrap.matv.io/pkg/* → conduit
      # reverse_proxy → vista-host DNAT → here). Files staged on the vista
      # HOST; migrated off conduit's local file_server 2026-08.
      "/var/lib/malli-bootstrap" = {
        hostPath = "/var/lib/malli-bootstrap";
        isReadOnly = true;
      };
      # registry.nix is no longer the inventory source — deus-server
      # now reads from headscale (deus v0.12+). Roles live in
      # /var/lib/deus/roles.json (small JSON, operator-edited),
      # which is in the bind-mounted /var/lib/deus tree.
    };

    config = { pkgs, ... }: let
      # ── Headscale ACL policy ──────────────────────────────
      # Default-allow becomes default-deny the moment any ACL is set,
      # so the first rule below MUST preserve fleet behaviour: the
      # `malli` user (which owns every fleet node) gets full mesh.
      # Each subsequent rule is a per-guest carve-out: a separate user
      # whose devices can reach exactly one host on exactly the ports
      # we forward (operator SSH on 2222, Screen Sharing/VNC on 5900).
      #
      # Adding a guest:
      #   1. Append a host-IP entry below + an `acls` rule for the new user
      #      (mind the `@` suffix on usernames — see syntax note below)
      #   2. Validate before deploy:
      #        sudo headscale policy check --file <(nix eval --raw \
      #          '/home/matv/nix#nixosConfigurations.conduit.config.containers.headscale.config.services.headscale.settings.policy.path')
      #   3. nixos-rebuild this conduit config (reloads the inner container)
      #   4. `sudo headscale users create <name>`
      #   5. `sudo headscale preauthkeys create --user <name>`
      #   6. Send the user the preauth key + headscale.matv.io
      headscalePolicy = pkgs.writeText "headscale-policy.hujson" ''
        {
          // Host aliases — friendly names for tailnet IPs in the rules
          // below. Sequential allocation makes the IPs stable enough
          // that hardcoding is fine for now; revisit when the fleet
          // grows past a few guests.
          //
          // NOTE on syntax: headscale 0.26+ requires the `@` suffix on
          // user references in src/dst (e.g. `malli@`). Bare strings
          // are interpreted as host aliases and must be defined in
          // this `hosts` block. Tags use the `tag:` prefix; groups use
          // `group:`. Getting this wrong puts headscale in a crash
          // loop.
          "hosts": {
            "m-pg4i": "100.64.0.30/32",
          },

          "acls": [
            // Fleet user — every fleet node is registered under `malli`.
            // Full mesh preserves the pre-policy behaviour. Without this
            // rule, every fleet machine instantly loses tailnet access
            // to every other fleet machine.
            {
              "action": "accept",
              "src":    ["malli@"],
              "dst":    ["*:*"],
            },

            // owen — the first guest, assigned to m-pg4i. Can reach only
            // that host on the operator-forward ports (2222 VM SSH, 5900
            // VM Screen Sharing). Cannot reach any other fleet node,
            // conduit, or any service on m-pg4i other than those two.
            {
              "action": "accept",
              "src":    ["owen@"],
              "dst":    ["m-pg4i:2222,5900"],
            },
          ],
        }
      '';
    in {
      imports = [
        inputs.deus.nixosModules.server
        inputs.home-manager.nixosModules.home-manager
      ];

      system.stateVersion = "23.11";

      # ── Home-manager for fleet user ──────────────────────
      # Imports the same shell.nix daniel uses on his own
      # workstations, so SSHing into the container feels like
      # an interactive shell, not a stripped-down jail.
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bkp";
      home-manager.extraSpecialArgs = { inherit inputs vars; hostName = "headscale"; };
      home-manager.users.fleet = { ... }: {
        imports = [
          inputs.nix-index-database.homeModules.nix-index
          ../../home/shell.nix
        ];
        home.username = "fleet";
        home.homeDirectory = "/home/fleet";
        home.stateVersion = "23.11";
      };

      # The granter shells out to `headscale nodes list -o json` for
      # tailnet IP → node name resolution. Headscale's runtime dir is
      # mode 0750 (NixOS default), so non-headscale users can't even
      # traverse to the socket. Add deus to the headscale group rather
      # than relax dir permissions.
      users.users.deus.extraGroups = [ "headscale" ];

      # The deus-fleet-recover.service runs as fleet and shells out to
      # `headscale nodes list -o json` to find candidates. Headscale's
      # /run dir is 0750 even though the socket file itself is 0666,
      # so without group membership the call returns "permission
      # denied" silently and the recovery sweep finds zero candidates
      # regardless of how many penalty-boxed Macs exist.
      # fleet user's extraGroups consolidated below at the main
      # users.users.fleet block (was a duplicate definition that
      # nix's module system rejected).

      # Allow deus user to start the malli-nix mirror oneshot service.
      # The granter triggers this after each git push so subsequent
      # `nixos-rebuild --refresh` calls on fleet VMs see the new
      # commit. Without this, the granter has no way to ensure the
      # mirror is fresh before returning success to the agent.
      #
      # nixos-container builds a minimal closure — polkit is NOT pulled
      # in by default and `security.polkit.extraConfig` is silently
      # no-op'd if the daemon isn't running. Without enable=true, the
      # rule loads onto disk but nothing enforces it, so the granter's
      # `systemctl start malli-nix-mirror.service` returns "Access
      # denied" and bootstrap stalls in the granter step.
      security.polkit.enable = true;
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              subject.user == "deus" &&
              action.lookup("verb") == "start" &&
              action.lookup("unit") == "malli-nix-mirror.service") {
            return polkit.Result.YES;
          }
        });
      '';

      # ── Deus fleet control plane ──────────────────────────
      services.deus.server = {
        enable = true;
        address = "0.0.0.0";
        port = 8086;
        # registryFile = null (default) — inventory comes from headscale.
        # Roles live in /var/lib/deus/roles.json (operator-edited).
        operatorTokenFile = "/var/lib/deus-tokens/operator-token";
        agentTokenFile = "/var/lib/deus-tokens/agent-token";
        # Read-only lookup scope for the AWS orchestrator (GET /fleet/bots/{uid}).
        # Same value must be stored in AWS Secrets Manager as DEUS_SERVICE_TOKEN.
        serviceTokenFile = "/var/lib/deus-tokens/service-token";

        # SSH-push deploys (Colmena model). deus-server claims pending
        # deploy jobs and SSHes to the target as tars/lima, runs
        # *-rebuild directly. Agents no longer poll /agent/commands.
        # Why: macOS murders user LaunchAgents (EX_CONFIG penalty
        # box) so an agent-pull deploy path is unreliable; sshd is
        # launchd-blessed + SACL-protected and stays alive. Same key
        # the recovery loop already uses (fleet@headscale).
        sshKeyFile = "/var/lib/deus/fleet-key";
        # sshKnownHostsFile, sshFlakeURL, sshLogDir, sshMaxConcurrent
        # use module defaults.

        # ── User-VPN integration ──
        # Lets deus-server mint/revoke VPN tunnels through
        # malli-uservpn-server and run a boot-time sync of existing
        # tokens into the users table. Both services already share
        # the same operator token (see operatorTokenFile above + the
        # comment in ../user-vpn.nix), so we just point at it again.
        uservpnTokenFile = "/var/lib/deus-tokens/operator-token";

        # ── Granter ──
        # Cloudflare per-device provisioning (Twilio was removed in
        # deus 0.16.0). The credential files are populated by the
        # activation script in this same module from sops secrets
        # defined in secrets.nix. Account/zone IDs are config, not
        # secrets.
        granter = {
          enable = true;
          domain = "themalli.ai";
          cfAPITokenFile = "/etc/deus-granter/cloudflare-token";
          cfAccountIDFile = "/etc/deus-granter/cf-account-id";
          cfZoneIDFile = "/etc/deus-granter/cf-zone-id";
          # GIT_SSH_COMMAND fully specifies the identity, so no
          # `Host github-malli-nix-write` SSH alias is needed — git just
          # invokes `ssh git@github.com` and the wrapper picks the key.
          repoURL = "git@github.com:NRE-Product/malli-nix.git";
          repoSSHCommand = "ssh -i /var/lib/deus/malli-nix-write -o IdentitiesOnly=yes -o UserKnownHostsFile=/var/lib/deus/known_hosts -o StrictHostKeyChecking=accept-new";
          # GitHub App auth (malli-granter): with all three set, the granter
          # mints installation tokens and pushes over HTTPS as the App, which
          # is in malli-nix's ruleset bypass — so registry/roles/secrets writes
          # land on the branch-protected main. repoURL is reused (converted to
          # https internally); repoSSHCommand above is inert in app mode.
          githubAppId = "4640298";
          githubAppInstallationId = "154761960";
          githubAppKeyFile = "/var/lib/deus/github-app-key";
        };

        # ── ADE / zero-touch orchestrator ──
        # Drives Apple Automated Device Enrollment through the self-hosted
        # nanomdm runs on vista (hosts/vista/mdm.nix, migrated from mantle
        # 2026-08). The nanomdm API key doubles as the webhook ?token= secret,
        # so the one staged file feeds both flags. nanomdm POSTs every
        # check-in/ack back to deus at http://10.100.0.1:8086/ade/webhook.
        ade = {
          # deus is inside vista's nspawn (a wg spoke) and reaches nanomdm via
          # the conduit hub, which socat-forwards :9990 → vista's nanomdm
          # (10.100.0.4:9990). Webhook back posts to conduit 10.100.0.1:8086,
          # which forwards here. (Local veth wiring is a deferred optimization.)
          nanomdmURL = "http://10.100.0.1:9990"; # conduit socat → vista 10.100.0.4
          apiKeyFile = "/var/lib/deus-tokens/nanomdm-api";
          webhookSecretFile = "/var/lib/deus-tokens/nanomdm-api";

          # Managed admin the AccountConfiguration step creates on each
          # Mac. "tars" (== vars.user.name) so auto-login-as-tars works,
          # SecureToken escrows to tars, and the nix-darwin fleet config
          # (which manages user tars) aligns. Confirmed decision.
          adminUsername = "tars";
          # Known fleet-wide admin password (Daniel's call) — every ADE-
          # provisioned Mac gets tars with this password instead of a
          # per-device random one.
          adminPassword = "tech123";

          # ── Bootstrap-creds vend (POST /ade/bootstrap-creds) ────────
          # Fleet nodes register under the headscale `malli` user (see
          # the ACL policy above: src ["malli@"] is the full-mesh rule).
          # The deus user can run `headscale` directly here — the unix
          # socket is 0666 and deus is in the headscale group.
          headscaleUser = "malli";
          headscaleCommand = "headscale";
          loginServer = "https://headscale.matv.io";
          malliNixURL = "git://conduit/malli-nix.git";
          # Age key gated on the sops secret being present (see top of
          # file). Empty until then → vend stays disabled, no crash.
          ageKeyFile = lib.optionalString haveFleetAgeKey "/var/lib/deus-tokens/fleet-age-key";

          # ── Post-account-creation push ──────────────────────────────
          # Trust profile first (so the Mac trusts our self-signed pkg
          # signer), then the bootstrap pkg. Gated on the committed
          # .mobileconfig; empty until then → profile step skipped.
          trustProfileFile = lib.optionalString haveTrustProfile "/var/lib/deus-tokens/installer-trust.mobileconfig";
          # The 5 fleet config profiles (fda grants Full Disk Access — the
          # SIP-on replacement for the old TCC.db hack). No sysext profile:
          # the fleet runs the tailscaled daemon, not the GUI app.
          profilesDir = lib.optionalString haveProfiles "/var/lib/deus-tokens/profiles";

          # Bootstrap pkg (InstallEnterpriseApplication). Rebuild + re-sign
          # in malli-nix, stage on the vista HOST (served by the in-container
          # Caddy :8088 via the /var/lib/malli-bootstrap bind-mount), re-hash:
          #   nix build '.#bootstrap-ade-pkg'   # in malli-nix (unsigned)
          #   nix run '.#sign-bootstrap-pkg' -- installer.pem result signed.pkg
          #   scp signed.pkg vista:/tmp && ssh vista sudo install -m0644 \
          #       /tmp/signed.pkg /var/lib/malli-bootstrap/malli-ade-bootstrap-0.1.0.pkg
          #   md5sum signed.pkg ; stat -c%s signed.pkg
          pkgURL = "https://bootstrap.matv.io/pkg/malli-ade-bootstrap-0.1.0.pkg";
          # Payload-free pkg (postinstall fetches the payload tarball from
          # /pkg/malli-bootstrap-payload.tar.gz). Re-hash on every rebuild.
          # retire-lima cutover 2026-08-20 (11-step lima-free deus f9176c3a).
          pkgMD5 = "1cfe3f8290d1623844ec446873ab9247";
          pkgMD5Size = 12484;
        };
        # headscaleCommand defaults to `headscale nodes list -o json`,
        # which is exactly what we want; the unix socket is world-
        # readable (see unix_socket_permission below) so no sudo wrapper.
      };

      # Bootstrap DNS: real resolvers so headscale can fetch its DERP map
      # (controlplane.tailscale.com) and the git mirror can reach github at
      # startup. On conduit this was 100.100.100.100 (the HOST's tailscale
      # MagicDNS), but in this private-net nspawn there's no tailscale DNS
      # until the container's OWN tailscale is up — which needs headscale,
      # which needs DNS (chicken-and-egg). Once tailscaled joins with
      # --accept-dns=true it registers split DNS via systemd-resolved so
      # tail.matv.io (m-xxxx fleet hosts) resolves via MagicDNS while
      # everything else keeps using these upstreams.
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
      networking.search = [ "tail.matv.io" ];
      # Don't inherit the host's resolv.conf — in a private-net container the
      # host's 127.0.0.53 stub points at the CONTAINER's own (empty) loopback,
      # so DNS is dead. Let the container manage its own resolv.conf instead
      # (required anyway once resolved is enabled below).
      networking.useHostResolvConf = false;
      # Run systemd-resolved INSIDE the container so the 127.0.0.53 stub that
      # nspawn wires up actually has a listener (upstreaming to the nameservers
      # above). Without this the container has no working DNS at all and
      # headscale crash-loops fetching its DERP map. resolved is also what
      # tailscale integrates with for split DNS (tail.matv.io → MagicDNS) once
      # the container's tailscaled joins.
      services.resolved.enable = true;

      # Open the service ports in the CONTAINER's own firewall. On conduit the
      # nspawn used host networking so the host firewall covered these; a
      # private-net container has its own netns + firewall. (2222 is already
      # opened by the sshd below.) Reached from the vista host / conduit via the
      # DNAT rules on the host side.
      networking.firewall.allowedTCPPorts = [ 8085 8086 8088 9418 ];

      # ── Static file server for the ADE bootstrap pkg + payload ────
      # Serves /var/lib/malli-bootstrap (host bind-mount, ro) on :8088.
      # conduit's public Caddy reverse_proxies bootstrap.matv.io/pkg/* →
      # vista:8088 (host DNAT → this container). Plain HTTP; TLS terminates
      # at conduit. handle_path strips the /pkg prefix so /pkg/foo maps to
      # /var/lib/malli-bootstrap/foo. Migrated off conduit's file_server 2026-08.
      services.caddy.enable = true;
      services.caddy.virtualHosts.":8088".extraConfig = ''
        handle_path /pkg/* {
          root * /var/lib/malli-bootstrap
          file_server
        }
        handle {
          respond "not found" 404
        }
      '';

      # ── Tailscale (INSIDE the nspawn — self-contained) ────
      # The container joins the malli tailnet as its OWN node ("deus-vista")
      # so deus can SSH the Macs (ssh tars@m-xxxx) exactly as it did via
      # conduit's host tailscale. It logs in against its OWN local Headscale
      # (http://localhost:8085) — no dependency on conduit/Caddy for the daemon
      # to come up. /dev/net/tun + CAP_NET_ADMIN come from `enableTun` on the
      # container. --accept-dns gives it MagicDNS (100.100.100.100) so the
      # `m-xxxx` names above resolve.
      services.tailscale.enable = true;

      # Bootstrap: mint a reusable preauth key from the local Headscale and
      # bring tailscale up once. Idempotent (skips if already Running). The
      # migrated DB already holds the `malli` user + all fleet nodes.
      systemd.services.deus-tailscale-up = {
        description = "Join the nspawn to the malli tailnet via local Headscale";
        after = [ "headscale.service" "tailscaled.service" ];
        requires = [ "headscale.service" "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.tailscale pkgs.jq config.services.headscale.package ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # wait for the local headscale API to answer
          for i in $(seq 1 60); do headscale nodes list -o json >/dev/null 2>&1 && break; sleep 2; done
          # already joined?
          if tailscale status --json 2>/dev/null | jq -e '.BackendState=="Running"' >/dev/null 2>&1; then
            echo "tailscale already Running"; exit 0
          fi
          # resolve the malli user's numeric id (this headscale build wants a
          # numeric --user, not the name), creating it only if somehow absent.
          headscale users create malli >/dev/null 2>&1 || true
          uid=$(headscale users list -o json 2>/dev/null | jq -r '.[]|select(.name=="malli")|.id' | head -1)
          if [ -z "$uid" ]; then echo "no malli user"; exit 1; fi
          key=$(headscale preauthkeys create --user "$uid" --reusable --expiration 1h 2>/dev/null \
                | grep -oE 'hskey-[A-Za-z0-9._-]+' | head -1)
          if [ -z "$key" ]; then echo "failed to mint preauth key"; exit 1; fi
          tailscale up --login-server http://localhost:8085 --authkey "$key" \
            --hostname deus-vista --accept-dns=true
        '';
      };

      # ── Headscale ────────────────────────────────────────
      services.headscale = {
        enable = true;
        # 0.0.0.0 (was 127.0.0.1 on conduit) so the host's forwardPorts DNAT
        # reaches it on the container's veth address — conduit's Caddy proxies
        # headscale.matv.io → vista:8085 → here. The container's own tailscaled
        # also logs in against this via http://localhost:8085.
        address = "0.0.0.0";
        port = 8085;

        settings = {
          server_url = "https://headscale.matv.io";
          dns = {
            magic_dns = true;
            base_domain = "tail.matv.io";
            override_local_dns = true;
            nameservers.global = [ "1.1.1.1" "1.0.0.1" ];
          };
          prefixes = {
            v4 = "100.64.0.0/10";
            v6 = "fd7a:115c:a1e0::/48";
            allocation = "sequential";
          };
          derp = {
            urls = [ "https://controlplane.tailscale.com/derpmap/default" ];
            auto_update_enabled = true;
            update_frequency = "3h";
          };
          database = {
            type = "sqlite";
            sqlite = {
              path = "/var/lib/headscale/db.sqlite";
              write_ahead_log = true;
            };
          };
          logtail.enabled = false;
          disable_check_updates = true;
          node.expiry = 0;
          # Allow the deus user (granter) to call `headscale nodes list`
          # directly. Single-tenant container, only resident processes
          # are headscale and deus-server, so 0666 is fine.
          unix_socket_permission = "0666";
          # ACL policy file. headscale watches this path and reloads on
          # change; the in-place container reload activation script
          # bounces the headscale unit when the path itself changes
          # (every nix-store rebuild of the policy).
          policy = {
            mode = "file";
            path = toString headscalePolicy;
          };
        };
      };

      # ── SSH for fleet operators ───────────────────────────
      services.openssh = {
        enable = true;
        ports = [ 2222 ];
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
        extraConfig = "UsePAM yes";
      };

      # PAM fix for OpenSSH 10.x (same as fleet VMs)
      security.pam.services.sshd.rules.auth.permit_pubkey = {
        order = 12400;
        control = "sufficient";
        modulePath = "pam_permit.so";
      };

      # Fix authorized_keys.d permissions for OpenSSH 10.x.
      # Plus copy the deploy key from the host bind-mount into fleet's
      # home with strict perms so SSH accepts it as an identity file.
      # Also pre-create the git mirror dir so the systemd timers below
      # can clone into it on first run.
      systemd.tmpfiles.rules = [
        "d /etc/ssh/authorized_keys.d 0755 root root -"
        "d /home/fleet/.ssh 0700 fleet users -"
        "C+ /home/fleet/.ssh/deploy_key_deus 0600 fleet users - /etc/deus-keys/deploy-malli-deus"
        # malli-nix READ deploy key (github.com) for the git mirror. Formalized
        # from the hand-placed key that was on conduit.
        "C+ /home/fleet/.ssh/deploy_key 0600 fleet users - /etc/deus-keys/deploy-malli-nix"
        "d /var/lib/git-mirror 0755 fleet users -"
        # Granter pushes to malli-nix on GitHub from inside the deus-server
        # systemd unit. Pre-seed github.com host keys so the push doesn't
        # block on an interactive prompt. Owned by deus (the container's
        # deus user; this rule runs inside the container's NixOS, where
        # the user exists).
        "f /var/lib/deus/known_hosts 0644 deus deus - github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
        # The granter's malli-nix write key lives at /etc/deus-keys
        # (root-owned 0750 from the host bind mount) which the deus user
        # can't traverse. Copy it into /var/lib/deus where deus owns the
        # tree, with strict perms so SSH accepts it as an identity file.
        "C+ /var/lib/deus/malli-nix-write 0600 deus deus - /etc/deus-keys/malli-nix-write"
        # GitHub App private key, same bind-mount → deus-owned copy pattern.
        # The granter reads it to mint installation tokens for pushing to
        # malli-nix (github-app auth mode; replaces the deploy-key push).
        "C+ /var/lib/deus/github-app-key 0600 deus deus - /etc/deus-keys/github-app-key"

        # SSH-push deploys: the deus user runs `ssh tars@m-XXXX sudo
        # darwin-rebuild …` to deploy. Reuse the fleet user's
        # id_ed25519 (already trusted by every Mac via fleet@headscale
        # in darwin-fleet.nix and every VM via vm-common.nix) by
        # copying it into /var/lib/deus where deus can read it. The
        # source key was created by hand on this container; if a
        # rebuild ever recreates it, this rule will refresh the copy.
        "C+ /var/lib/deus/fleet-key 0600 deus deus - /home/fleet/.ssh/id_ed25519"
        # Writable known_hosts so the dispatcher's accept-new can pin
        # each Mac/VM key on first contact. Empty file at boot; SSH
        # appends as it discovers hosts.
        "f /var/lib/deus/fleet-known-hosts 0644 deus deus -"
      ];


      # ── Tailnet-internal git mirror ───────────────────────
      # Fleet machines fetch flake sources from `git+git://conduit/...`
      # rather than GitHub, so they never need GitHub credentials. The
      # mirror lives in this container because the deploy keys it uses
      # to fetch from upstream already live here. git:// is plaintext
      # but the wireguard-encrypted tailnet is the trust boundary.
      services.gitDaemon = {
        enable = true;
        basePath = "/var/lib/git-mirror";
        exportAll = true;
        listenAddress = "0.0.0.0";
      };

      # Mirror service writes as `fleet`, daemon reads as `git` — git's
      # safe-directory check refuses cross-owner access otherwise.
      environment.etc.gitconfig.text = ''
        [safe]
        	directory = /var/lib/git-mirror/*
      '';

      systemd.services.malli-nix-mirror = {
        description = "Mirror malli-nix from GitHub";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ pkgs.git pkgs.openssh ];
        serviceConfig = {
          Type = "oneshot";
          User = "fleet";
          Group = "users";
          # Self-heal ownership: any time someone runs git ops in the
          # mirror as root (sudo git fsck, debugging, etc.), git creates
          # objects with root ownership, after which fleet-run fetches
          # silently fail with "insufficient permission for adding an
          # object." We hit this once and it stalled the fleet for hours
          # because the failure mode is invisible until bootstrap
          # Verify polls time out. ExecStartPre runs as root and
          # restores consistent ownership before the fetch.
          # Skip if the mirror hasn't been cloned yet (fresh host) — ExecStart
          # clones it as fleet with correct ownership; the chown only self-heals
          # a pre-existing tree. Without the guard the whole service fails on
          # first run and never clones.
          ExecStartPre = "+${pkgs.bash}/bin/bash -c 'test -d /var/lib/git-mirror/malli-nix.git && ${pkgs.coreutils}/bin/chown -R fleet:users /var/lib/git-mirror/malli-nix.git || true'";
          ExecStart = pkgs.writeShellScript "malli-nix-mirror" ''
            set -e
            cd /var/lib/git-mirror
            if [ ! -d malli-nix.git ]; then
              git clone --mirror git@github.com:NRE-Product/malli-nix.git
            fi
            git -C malli-nix.git fetch --all --prune
          '';
        };
      };

      systemd.timers.malli-nix-mirror = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "5m";
        };
      };

      systemd.services.malli-deus-mirror = {
        description = "Mirror malli-deus from GitHub";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ pkgs.git pkgs.openssh ];
        serviceConfig = {
          Type = "oneshot";
          User = "fleet";
          Group = "users";
          ExecStart = pkgs.writeShellScript "malli-deus-mirror" ''
            set -e
            cd /var/lib/git-mirror
            if [ ! -d malli-deus.git ]; then
              git clone --mirror git@github-malli-deus:NRE-Product/malli-deus.git
            fi
            git -C malli-deus.git fetch --all --prune
          '';
        };
      };

      systemd.timers.malli-deus-mirror = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "45s";
          OnUnitActiveSec = "5m";
        };
      };

      # ── Auto-recovery for Macs in launchd EX_CONFIG penalty box ───
      # macOS launchd flags the deus-agent daemon as "misbehaving" and
      # parks it in `state = spawn scheduled, last exit code = 78:
      # EX_CONFIG` after a few rapid bootout/bootstrap cycles — which
      # is what darwin-rebuild does whenever the deus binary version
      # bumps (because the launchd plist's runner script path changes).
      # The only recovery is a manual `launchctl bootout + bootstrap`,
      # which doesn't scale to 575 Macs. The watchdog daemon shipped
      # with the agent itself (in 0.16.10) tries to self-heal but can
      # itself hit the same trap if it spawns during a deploy storm.
      #
      # This timer polls every 5 min for "deus says offline + headscale
      # says online" Macs, SSHes in as fleet→tars, and runs the
      # bootout/bootstrap dance. fleet user already has SSH access to
      # tars@<mac> (id_ed25519 in /home/fleet/.ssh/) from earlier work.
      systemd.services.deus-fleet-recover = {
        description = "Recover Macs in launchd EX_CONFIG penalty box";
        after = [ "deus-server.service" "headscale.service" ];
        # bash is needed because the parallel-recover loop spawns a
        # `xargs -I {} bash -c ...` subshell per host. Without bash on
        # PATH, xargs fails with "bash: No such file or directory" and
        # the recovery is silently a no-op even when candidates exist.
        path = with pkgs; [ bash jq curl openssh gawk coreutils ];
        serviceConfig = {
          Type = "oneshot";
          User = "fleet";
          Group = "users";
          StandardOutput = "append:/var/log/deus-fleet-recover.log";
          StandardError = "append:/var/log/deus-fleet-recover.log";
          ExecStart = pkgs.writeShellScript "deus-fleet-recover" ''
            set -uo pipefail

            log() { echo "[$(date -u +%FT%TZ)] $*"; }

            TOKEN_FILE=/var/lib/deus-tokens/operator-token
            DEUS_URL=http://127.0.0.1:8086

            if [ ! -r "$TOKEN_FILE" ]; then
              log "operator token not readable; exiting"
              exit 0
            fi
            TOKEN=$(cat "$TOKEN_FILE")

            # Headscale snapshot. We need both lists: the Mac names are
            # candidate keys; the VM names tell us which "Tailscale
            # daemon stuck" cases we can rescue via a ProxyJump through
            # the Mac's Lima VM peer (192.168.5.2 is the Lima bridge).
            hs_json=$(${pkgs.headscale}/bin/headscale nodes list -o json 2>/dev/null || echo '[]')
            mapfile -t online_macs < <(
              echo "$hs_json" | jq -r '.[] | select(.online == true) | select(.given_name | test("^m-[a-z0-9]+$")) | .given_name'
            )
            mapfile -t online_vms < <(
              echo "$hs_json" | jq -r '.[] | select(.online == true) | select(.given_name | test("^m-[a-z0-9]+-vm$")) | .given_name'
            )

            # Hosts deus considers offline darwin-side.
            mapfile -t offline_macs < <(
              curl -sf -m 10 -H "Authorization: Bearer $TOKEN" "$DEUS_URL/hosts" 2>/dev/null \
                | jq -r '.[] | select(.kind == "darwin") | select(.health == "offline") | .name' \
                | sort -u
            )

            # Candidates: deus-offline Macs whose Mac OR -vm peer is
            # headscale-online. The VM-online branch is what lets us
            # reach Macs whose Tailscale daemon got stuck routing
            # inbound — direct SSH times out, but the peer's Lima
            # bridge gives us a back door.
            declare -A in_macs in_vms
            for o in "''${online_macs[@]:-}"; do in_macs[$o]=1; done
            for v in "''${online_vms[@]:-}"; do in_vms[$v]=1; done

            declare -a candidates=()
            for h in "''${offline_macs[@]:-}"; do
              if [ -n "''${in_macs[$h]:-}" ] || [ -n "''${in_vms[$h-vm]:-}" ]; then
                candidates+=("$h")
              fi
            done

            if [ "''${#candidates[@]}" -eq 0 ]; then
              log "no candidates"
              exit 0
            fi
            log "candidates (''${#candidates[@]}): ''${candidates[*]}"

            # Serialize the VM-online set for the recovery subshells —
            # bash arrays don't survive `xargs -I {} bash -c`, but an
            # exported space-separated string does.
            export ONLINE_VMS_LIST="''${online_vms[*]:-}"

            # SSH_OPTS: shared option set for every recovery SSH call.
            # UserKnownHostsFile=/dev/null is critical for the
            # ProxyJump path — Lima's bridge IP is 192.168.5.2 on
            # EVERY Mac, so caching that key per-Mac means recovery
            # only works for whichever Mac was visited first; every
            # other Mac then trips host-key-changed and the recover
            # silently fails. The tailnet is the trust boundary, so
            # not caching keys is acceptable. Same applies to the
            # direct path: a wipe-and-rebootstrap of a Mac generates
            # a new host key and we'd otherwise need manual cleanup.
            SSH_OPTS=(-o ConnectTimeout=5 -o BatchMode=yes
              -o StrictHostKeyChecking=no
              -o UserKnownHostsFile=/dev/null)

            # ssh_state returns the agent's launchd state string, OR
            # "_SSH_FAIL_" if we couldn't connect at all. Empty
            # (no "state =" line) means the agent isn't loaded —
            # which is itself a recoverable condition (we just need to
            # bootstrap fresh).
            ssh_state() {
              local out rc
              out=$(ssh "''${SSH_OPTS[@]}" \
                    "tars@$1" \
                    'sudo /bin/launchctl print system/io.matv.deus-agent 2>/dev/null | awk -F"= *" "/state =/{print \$2; exit}"' \
                    2>/dev/null)
              rc=$?
              if [ "$rc" -ne 0 ]; then
                echo "_SSH_FAIL_"
                return
              fi
              # Trim leading space awk leaves in.
              echo "$out" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            }

            # direct_bootstrap runs the bootout/bootstrap dance over a
            # plain SSH connection. Idempotent: bootout no-ops if the
            # unit isn't loaded, bootstrap no-ops if it already is.
            direct_bootstrap() {
              ssh "''${SSH_OPTS[@]}" \
                  "tars@$1" '
                sudo /bin/launchctl bootout system/io.matv.deus-agent 2>/dev/null || true
                sudo /bin/launchctl bootout system/io.matv.deus-agent-watchdog 2>/dev/null || true
                sleep 1
                sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/io.matv.deus-agent.plist 2>/dev/null || true
                sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/io.matv.deus-agent-watchdog.plist 2>/dev/null || true
              ' >/dev/null 2>&1
            }

            # rescue_via_vm tunnels through the Mac's Lima VM peer using
            # SSH ProxyJump, then bounces the Tailscale network
            # extension (whose service name carries a version suffix)
            # before reloading the deus-agent. Fixes the m-pc86 case:
            # Mac kernel + sshd alive locally, but the Tailscale
            # daemon's IPN extension stopped routing inbound — only a
            # kickstart of that extension brings it back.
            rescue_via_vm() {
              ssh "''${SSH_OPTS[@]}" \
                  -J "lima@$1-vm" tars@192.168.5.2 '
                svc=$(sudo /bin/launchctl list 2>/dev/null | grep -F "NetworkExtension.io.tailscale" | awk "{print \$3}" | head -1)
                if [ -n "$svc" ]; then
                  sudo /bin/launchctl kickstart -k "system/$svc" 2>/dev/null || true
                fi
                sleep 3
                sudo /bin/launchctl bootout system/io.matv.deus-agent 2>/dev/null || true
                sudo /bin/launchctl bootout system/io.matv.deus-agent-watchdog 2>/dev/null || true
                sleep 1
                sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/io.matv.deus-agent.plist 2>/dev/null || true
                sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/io.matv.deus-agent-watchdog.plist 2>/dev/null || true
              ' >/dev/null 2>&1
            }

            # has_vm_peer: is this Mac's -vm peer online in headscale?
            has_vm_peer() {
              local target="$1-vm"
              for v in $ONLINE_VMS_LIST; do
                [ "$v" = "$target" ] && return 0
              done
              return 1
            }

            recover_one() {
              local mac="$1" pre post
              pre=$(ssh_state "$mac")

              case "$pre" in
                _SSH_FAIL_)
                  # Direct SSH timed out. Only the VM-jumphost path
                  # can rescue this Mac. If no VM peer, nothing to do.
                  if has_vm_peer "$mac"; then
                    if rescue_via_vm "$mac"; then
                      echo "$mac: rescued via $mac-vm jumphost (tailscale + agent bounced)"
                    else
                      echo "$mac: jumphost rescue failed — skip"
                    fi
                  else
                    echo "$mac: ssh timeout + no $mac-vm peer online — skip"
                  fi
                  ;;
                "spawn scheduled"|"")
                  # spawn scheduled = EX_CONFIG penalty box.
                  # empty     = service not loaded at all (e.g. fresh
                  #             reboot where launchd never registered
                  #             the plist). Both fixed by the same
                  #             bootout/bootstrap dance.
                  if direct_bootstrap "$mac"; then
                    sleep 2
                    post=$(ssh_state "$mac")
                    echo "$mac: direct pre=''${pre:-(missing)} → post=''${post:-(missing)}"
                  else
                    echo "$mac: direct_bootstrap ssh failed — skip"
                  fi
                  ;;
                *)
                  # running/waiting/etc — agent is fine, deus's view
                  # is stale for another reason. Don't poke a healthy
                  # process.
                  echo "$mac: state=$pre — skip (agent appears healthy)"
                  ;;
              esac
            }

            export -f ssh_state direct_bootstrap rescue_via_vm has_vm_peer recover_one
            printf '%s\n' "''${candidates[@]}" \
              | xargs -P 8 -I {} bash -c 'recover_one "$@"' _ {} \
              | while IFS= read -r line; do log "$line"; done

            log "done"
          '';
        };
      };

      systemd.timers.deus-fleet-recover = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "5m";
        };
      };

      # ── Fleet user ────────────────────────────────────────
      users.users.fleet = {
        isNormalUser = true;
        # `headscale` group lets fleet user read /var/run/headscale's
        # 0750-perm dir for the recovery script's `headscale nodes
        # list` shellouts (see deus-fleet-recover service above).
        extraGroups = [ "wheel" "headscale" ];
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEODivGUKMXoxIyGkw6BWN023G2N1SL2yDi8lpulnc7R alan_ps@hotmail.com"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDTZdD7pKHnM5C/9WLs5SJbOSdW8Ee2H4GMi6rXcxM3FPXz5Md47zeBAsoQulFFGWDe5VaIueyt7ILXoSqMonz1kNDBjeGY0DCpVozd9iobzLRaoet3fKlvxvr35h/Z99YgltEWR/N/Dir7+4Mk2Tl80RWTx0RA6s3IHUsstCFWAxh175Maydspmaq0l1gsqvWEB1MZwGMUuZjGI53WKaQBRgHGMqBSoSANWpPrAdTYemkvf53RJiNuHHhZ5t5M73oCHvLviJ48FIWpOaKBp2l+b1R6fB6MBmCMoVUxgQYUZTyOyS81+wVKqjYWY19jfDRLH972cA679pm9y/+xnoNaAmdQ77qppbr+pEFxQmNQrNCggdpAyZKGl2Kfsp0guqWnG7sm7AjKMV2AF8hMSAp8vh9CGjEA4pu1vpHlZVOXRTAeT6pavmfbPDnBgOulALkRWydWGwMJkyoMnSyYo0Z+PxzgtHTlfeCYE19pOnnKqyIlUHpVP9M4kN1EluZT51c="
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGUH4FlVZkcKIanaFPMcb8vNy/FIGE8lGsGTA9dZSzIz matt@newreacheducation.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEj1O0FjhOogZaMYwhwntdmbytnQ/FPlaSbzmwGn0uQN calebd@newreach.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBSCDtHtHGA9EpNAUhm8WdrkPV7l/qKofLmiDcFipjBj arcbjorn@proton.me"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDWD39txIQueOEsZI81xCmtaFBNY3uyfnmjQyNh0hQ6s nathan@prop.ai"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEHBEru4yTx81hRzvT7gKuu7MGJBql85flqqrV63EBBq matias@newreach.com"
        ];
      };

      security.sudo.wheelNeedsPassword = false;

      # ── Packages available to fleet operators ─────────────
      environment.systemPackages = with pkgs; [
        htop
        jq
        curl
        vim
        bat
        tmux
        git
        sqlite # poke deus.db directly when needed (cleanup, audits)
        # deus CLI/TUI — operators run `deus` here to watch the fleet and
        # the provisioning dashboard (press P). Same package the server
        # module pulls in, so it's already in the container closure.
        inputs.deus.packages.${pkgs.system}.default
      ];

      programs.zsh.enable = true;

      # GitHub deploy keys are unique per repo, so two of them under
      # the same Host don't both work — first key wins and scopes the
      # connection. Use a per-repo alias for malli-deus; keep the
      # default github.com pointing at the existing malli-nix key so
      # `git pull` on the cloned malli-nix repo still works unchanged.
      programs.ssh.extraConfig = ''
        Host github.com
          IdentityFile /home/fleet/.ssh/deploy_key
          IdentitiesOnly yes

        Host github-malli-deus
          HostName github.com
          User git
          IdentityFile /home/fleet/.ssh/deploy_key_deus
          IdentitiesOnly yes

        Host *
          IdentityFile /home/fleet/.ssh/id_ed25519
          StrictHostKeyChecking accept-new
      '';

      nix.settings.experimental-features = [ "nix-command" "flakes" ];
    };
  };

  # ── In-place reload for headscale container ─────────────────
  # Companion to `containers.headscale.restartIfChanged = false`
  # above. On every host activation, compare the freshly-built
  # container closure to whatever the container is currently running;
  # on mismatch, ask container@headscale.service to reload — which
  # does `nixos-container run -- switch-to-configuration test` inside
  # the container. New systemd units, new binary versions, sops
  # template tweaks etc. apply via a per-unit restart only, no nspawn
  # bounce. The `|| true` keeps activation green even on first ever
  # boot when the container hasn't started yet (autoStart picks it
  # up moments later).
  system.activationScripts.reload-headscale-container = lib.stringAfter [ "etc" ] ''
    if ${pkgs.systemd}/bin/systemctl is-active container@headscale.service >/dev/null 2>&1; then
      desired=${config.containers.headscale.path}
      current=$(${pkgs.coreutils}/bin/readlink -f /var/lib/nixos-containers/headscale/run/current-system 2>/dev/null || true)
      if [ "$desired" != "$current" ]; then
        echo "container@headscale: inner closure changed, reloading"
        ${pkgs.systemd}/bin/systemctl reload container@headscale.service || true
      fi
    fi
  '';

  # ── NAT/forwarding for the private-network nspawn ──────────
  # The container (10.100.1.2, host-side veth ve-headscale = 10.100.1.1) needs
  # egress for: the git mirror (github.com), its own tailscaled (DERP +
  # controlplane), and reaching conduit (10.100.0.1:9990 for ADE via wg0).
  # Interface-agnostic: forward the veth both ways and masquerade the container
  # subnet onto whatever egress path (uplink for internet, wg0 for conduit).
  #
  # Inbound service ports: nixos-container forwardPorts doesn't install its DNAT
  # on this NM host, so do it explicitly — DNAT the service ports arriving at
  # vista (from conduit over wg0, or the public :2222) to the container at
  # 10.100.1.2. PREROUTING catches forwarded + redirected-local traffic.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  networking.firewall.extraCommands = ''
    iptables -t nat -C POSTROUTING -s 10.100.1.0/24 ! -d 10.100.1.0/24 -j MASQUERADE 2>/dev/null \
      || iptables -t nat -A POSTROUTING -s 10.100.1.0/24 ! -d 10.100.1.0/24 -j MASQUERADE
    iptables -C FORWARD -i ve-headscale -j ACCEPT 2>/dev/null || iptables -A FORWARD -i ve-headscale -j ACCEPT
    iptables -C FORWARD -o ve-headscale -j ACCEPT 2>/dev/null || iptables -A FORWARD -o ve-headscale -j ACCEPT
    for p in 8085 8086 8088 9418 2222; do
      iptables -t nat -C PREROUTING -p tcp --dport $p -j DNAT --to-destination 10.100.1.2:$p 2>/dev/null \
        || iptables -t nat -A PREROUTING -p tcp --dport $p -j DNAT --to-destination 10.100.1.2:$p
    done
  '';

  # ── Bring up + address the container veth ──────────────────
  # NixOS private-network containers expect systemd-networkd to configure the
  # host side of the veth (ve-headscale). vista uses NetworkManager, which
  # leaves ve-headscale unmanaged + DOWN, so the container has no gateway/egress.
  # This service is triggered by the veth device appearing (which nspawn creates
  # on container start), so it fires on first boot AND on every container
  # restart — bringing the link up and assigning the gateway address the
  # container routes through (hostAddress = 10.100.1.1).
  systemd.services."ve-headscale-setup" = {
    description = "Bring up + address the headscale container veth (NM host)";
    bindsTo = [ "sys-subsystem-net-devices-ve\\x2dheadscale.device" ];
    after = [ "sys-subsystem-net-devices-ve\\x2dheadscale.device" ];
    wantedBy = [ "sys-subsystem-net-devices-ve\\x2dheadscale.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iproute2}/bin/ip link set ve-headscale up
      ${pkgs.iproute2}/bin/ip addr replace 10.100.1.1/24 dev ve-headscale
    '';
  };

  # Keep NetworkManager's hands off the container veth (belt-and-suspenders;
  # it already reports ve-headscale unmanaged, but pin it so a NM restart
  # doesn't grab + reconfigure it).
  networking.networkmanager.unmanaged = [ "interface-name:ve-headscale" ];

}
