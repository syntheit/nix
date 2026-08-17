# ─────────────────────────────────────────────────────────────────────────────
# MDM stack for the Mac mini fleet — fully containerised (easy to move servers).
#
#   nanomdm  — the MDM server: pushes config profiles + commands to enrolled Macs
#   scep     — device-identity CA: issues the certs nanomdm validates
#
# Both are built as our own minimal Docker images from the upstream release binaries
# (the official nanomdm image is distroless and only reads CLI args, which would force
# the API key into the nix store; our tiny entrypoint reads it from the sops env file at
# runtime instead). Design notes: ~/Projects/malli-deus/plans/phase-2-mdm-and-profiles.md
#
# All persistent data lives under ONE directory (tar it to back up / move servers):
#   /arespool/appdata/mdm/nanomdm/   → nanomdm /app/db    (devices, queue, APNs push cert)
#   /arespool/appdata/mdm/scep/      → scep /depot         (ca.pem, ca.key, issued certs)
#
# Exposed via the existing harbor cloudflared tunnel (mdm.matv.io / scep.matv.io) — no
# public IP. Device auth works behind Cloudflare's TLS termination via SignMessage=true in
# the enrollment profile (Mdm-Signature header) — nanomdm's default, no client-cert passthrough.
# ─────────────────────────────────────────────────────────────────────────────
{ config, pkgs, lib, ... }:

let
  dataDir = "/var/lib/mdm";
  scepHostPort = 8081;
  nanomdmHostPort = 9990; # 9000 is already taken on harbor

  # Pin upstream release binaries (statically linked, verified to run on NixOS) and wrap
  # each in a minimal Docker image so the whole stack is containers.
  fetchRelease = { repo, asset, ver, hash }: pkgs.fetchurl {
    url = "https://github.com/micromdm/${repo}/releases/download/v${ver}/${asset}-linux-amd64-v${ver}.zip";
    sha256 = hash;
  };

  scepserver = pkgs.stdenv.mkDerivation {
    pname = "scepserver"; version = "2.3.0";
    src = fetchRelease { repo = "scep"; asset = "scepserver"; ver = "2.3.0"; hash = "0igql15nqgbrcjifhizyd4sa36b62bl44aq136mars6yllhrchnb"; };
    nativeBuildInputs = [ pkgs.unzip pkgs.autoPatchelfHook ];
    dontConfigure = true; dontBuild = true;
    unpackPhase = "unzip $src";
    installPhase = "install -Dm0755 scepserver-linux-amd64 $out/bin/scepserver";
  };

  nanomdm = pkgs.stdenv.mkDerivation {
    pname = "nanomdm"; version = "0.6.0";
    src = fetchRelease { repo = "nanomdm"; asset = "nanomdm"; ver = "0.6.0"; hash = "0j2cjnv84pyyj8pa10kniwbj6f0f9g7q6rxmw9kzldjvdb80l2gd"; };
    nativeBuildInputs = [ pkgs.unzip pkgs.autoPatchelfHook ];
    dontConfigure = true; dontBuild = true;
    unpackPhase = "unzip $src";
    # the nanomdm zip extracts into a versioned subdir
    installPhase = "install -Dm0755 nanomdm-linux-amd64-v0.6.0/nanomdm-linux-amd64 $out/bin/nanomdm";
  };

  # nanodep — the ABM/ADE (DEP) connector: links nanomdm to Apple Business so Macs
  # auto-enroll. Internal/operator-facing only (Apple is reached OUTBOUND), so no tunnel.
  nanodep = pkgs.stdenv.mkDerivation {
    pname = "nanodep"; version = "0.7.0";
    src = fetchRelease { repo = "nanodep"; asset = "nanodep"; ver = "0.7.0"; hash = "1wzl0sjyry4phcf118yfgk6fzs4h4rw3z7ql9zi2s8k4jkjwway6"; };
    nativeBuildInputs = [ pkgs.unzip pkgs.autoPatchelfHook ];
    dontConfigure = true; dontBuild = true;
    unpackPhase = "unzip $src";
    installPhase = ''
      install -Dm0755 nanodep-linux-amd64-v0.7.0/depserver-linux-amd64 $out/bin/depserver
      install -Dm0755 nanodep-linux-amd64-v0.7.0/deptokens-linux-amd64 $out/bin/deptokens
      install -Dm0755 nanodep-linux-amd64-v0.7.0/depsyncer-linux-amd64 $out/bin/depsyncer
    '';
  };

  scepEntry = pkgs.writeShellScript "scep-entrypoint" ''
    set -e
    DEPOT=/depot
    [ -f "$DEPOT/ca.pem" ] || ${scepserver}/bin/scepserver ca -init -depot "$DEPOT"
    exec ${scepserver}/bin/scepserver -depot "$DEPOT" -port 8080 \
      -challenge "$SCEP_CHALLENGE" -allowrenew 0 -crtvalid 365
  '';

  nanomdmEntry = pkgs.writeShellScript "nanomdm-entrypoint" ''
    set -e
    : "''${NANOMDM_API:?NANOMDM_API must be set (sops nanomdm.env)}"
    # -webhook-url feeds every check-in + command ack to deus's ADE
    # orchestrator (running in the headscale container on conduit,
    # reachable over the harbor↔conduit WireGuard link at 10.100.0.1).
    # The ?token= is the shared secret deus verifies; we reuse NANOMDM_API
    # for it (deus already needs that key for the enqueue API, so it's the
    # one secret both ends share — no second cross-host secret to manage).
    exec ${nanomdm}/bin/nanomdm \
      -ca /app/scep/ca.pem \
      -api "$NANOMDM_API" \
      -storage file -storage-dsn /app/db \
      -webhook-url "http://10.100.0.1:8086/ade/webhook?token=$NANOMDM_API" \
      -listen :9000
  '';

  nanodepEntry = pkgs.writeShellScript "nanodep-entrypoint" ''
    set -e
    : "''${NANODEP_API:?NANODEP_API must be set}"
    exec ${nanodep}/bin/depserver -api "$NANODEP_API" \
      -storage filekv -storage-dsn /app/db -listen :9001
  '';

  # ── ADE enrollment-profile server ──────────────────────────────────────────
  # nanomdm does NOT serve enrollment profiles. For Automated Device Enrollment
  # the Mac POSTs (with an x-apple-aspen-deviceinfo header) to the DEP profile's
  # `url` and expects the enrollment .mobileconfig back as
  # `application/x-apple-aspen-config`. So we host that one static profile here
  # (exposed publicly as https://enroll.matv.io/enroll via the harbor tunnel).
  #
  # The SCEP challenge is a SECRET, so it must NOT land in the world-readable nix
  # store: we ship a template with an @SCEP_CHALLENGE@ placeholder and substitute
  # it at runtime from the sops-rendered scep.env (same SCEP_CHALLENGE the scep
  # container uses). The rendered profile is held in memory and never written to disk.
  enrollProfileTmpl = pkgs.writeText "enroll.mobileconfig.tmpl" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>PayloadContent</key>
      <array>
        <dict>
          <key>PayloadContent</key>
          <dict>
            <key>Key Type</key>
            <string>RSA</string>
            <key>Challenge</key>
            <string>@SCEP_CHALLENGE@</string>
            <key>Key Usage</key>
            <integer>5</integer>
            <key>Keysize</key>
            <integer>2048</integer>
            <key>URL</key>
            <string>https://scep.matv.io/scep</string>
            <!-- Non-empty Subject is REQUIRED: an empty-subject device cert
                 makes determinate-nixd panic enumerating the System keychain
                 (SecCertificate subject_summary = NULL), breaking /nix mounts.
                 %SerialNumber% is substituted on-device at CSR time. -->
            <key>Subject</key>
            <array>
              <array>
                <array>
                  <string>CN</string>
                  <string>%SerialNumber%</string>
                </array>
              </array>
            </array>
          </dict>
          <key>PayloadIdentifier</key>
          <string>io.matv.fleet.enroll.scep</string>
          <key>PayloadType</key>
          <string>com.apple.security.scep</string>
          <key>PayloadUUID</key>
          <string>CE5DBA22-BDB3-4BE3-949D-3DBF2E29BB0F</string>
          <key>PayloadVersion</key>
          <integer>1</integer>
        </dict>
        <dict>
          <key>AccessRights</key>
          <integer>8191</integer>
          <key>CheckOutWhenRemoved</key>
          <true/>
          <key>IdentityCertificateUUID</key>
          <string>CE5DBA22-BDB3-4BE3-949D-3DBF2E29BB0F</string>
          <key>PayloadIdentifier</key>
          <string>io.matv.fleet.enroll.mdm</string>
          <key>PayloadType</key>
          <string>com.apple.mdm</string>
          <key>PayloadUUID</key>
          <string>D836CE60-50F0-465F-B781-B4005D6073CE</string>
          <key>PayloadVersion</key>
          <integer>1</integer>
          <key>ServerCapabilities</key>
          <array>
            <string>com.apple.mdm.per-user-connections</string>
            <string>com.apple.mdm.bootstraptoken</string>
            <string>com.apple.mdm.token</string>
          </array>
          <key>ServerURL</key>
          <string>https://mdm.matv.io/mdm</string>
          <key>SignMessage</key>
          <true/>
          <key>Topic</key>
          <string>com.apple.mgmt.External.9e86f5d9-9ab5-4642-8a3d-146a7a969fae</string>
        </dict>
      </array>
      <key>PayloadDisplayName</key>
      <string>Malli MDM Enrollment</string>
      <key>PayloadIdentifier</key>
      <string>io.matv.fleet.enroll</string>
      <key>PayloadOrganization</key>
      <string>New Reach, LLC</string>
      <key>PayloadScope</key>
      <string>System</string>
      <key>PayloadType</key>
      <string>Configuration</string>
      <key>PayloadUUID</key>
      <string>2651843B-7A4C-4611-A625-C027CCE6D8E8</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    </plist>
  '';

  # Tiny HTTP server: renders the template once (substituting the secret from
  # $SCEP_CHALLENGE) and returns it for GET/HEAD/POST on any path with the
  # Apple enrollment content-type. POST is required — ADE devices POST their
  # signed deviceinfo to the url.
  enrollServe = pkgs.writeText "enroll-serve.py" ''
    import http.server, socketserver, os
    with open(os.environ["ENROLL_TEMPLATE"], "r") as f:
        PROFILE = f.read().replace("@SCEP_CHALLENGE@", os.environ["SCEP_CHALLENGE"]).encode()
    PORT = int(os.environ.get("PORT", "8080"))
    class H(http.server.BaseHTTPRequestHandler):
        def _send(self, body=True):
            self.send_response(200)
            self.send_header("Content-Type", "application/x-apple-aspen-config")
            self.send_header("Content-Length", str(len(PROFILE)))
            self.end_headers()
            if body:
                self.wfile.write(PROFILE)
        def do_GET(self):  self._send(True)
        def do_HEAD(self): self._send(False)
        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0) or 0)
            if n:
                self.rfile.read(n)
            self._send(True)
        def log_message(self, *a): pass
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), H) as httpd:
        httpd.serve_forever()
  '';

  enrollEntry = pkgs.writeShellScript "enroll-entrypoint" ''
    set -e
    : "''${SCEP_CHALLENGE:?SCEP_CHALLENGE must be set (sops scep.env)}"
    export ENROLL_TEMPLATE="${enrollProfileTmpl}"
    export PORT=8080
    exec ${pkgs.python3}/bin/python3 ${enrollServe}
  '';

  mkImage = name: tag: entry: ports: vols: pkgs.dockerTools.buildImage {
    inherit name tag;
    # CA bundle — outbound HTTPS (Apple DEP API, APNs) must verify Apple's certs;
    # minimal dockerTools images ship no root CAs otherwise.
    copyToRoot = [ pkgs.cacert ];
    config = {
      Entrypoint = [ "${entry}" ];
      Env = [ "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
      ExposedPorts = lib.genAttrs ports (_: { });
      Volumes = lib.genAttrs vols (_: { });
    };
  };

  scepImage = mkImage "malli-scep" "2.3.0" scepEntry [ "8080/tcp" ] [ "/depot" ];
  nanomdmImage = mkImage "malli-nanomdm" "0.6.0" nanomdmEntry [ "9000/tcp" ] [ "/app/db" ];
  nanodepImage = mkImage "malli-nanodep" "0.7.0" nanodepEntry [ "9001/tcp" ] [ "/app/db" ];

  # The enroll server needs python3 (not a release binary), so it builds its own
  # image rather than going through mkImage. No outbound TLS → no cacert needed.
  enrollImage = pkgs.dockerTools.buildImage {
    name = "malli-mdmenroll"; tag = "1.0.0";
    copyToRoot = [ pkgs.python3 ];
    config = {
      Entrypoint = [ "${enrollEntry}" ];
      ExposedPorts = { "8080/tcp" = { }; };
    };
  };

  # ── DEP auto-assigner ───────────────────────────────────────────────────────
  # The fleet enrollment profile in Apple Business (pushed by deus, uuid below).
  # A brand-new Mac added to ABM lands with profile_status "empty" and Setup
  # Assistant SKIPS the ADE enroll step until a profile is assigned — so a device
  # can't auto-provision until this runs. nanodep has no default-profile flag and
  # runs no syncer, so nothing attaches it automatically. This script (driven by a
  # 5-min timer below) closes that gap.
  depName = "malli";
  depProfileUUID = "D0282F6826CFFE503334FD0B594BF0F1";

  # curl + jq only (no python3 needed → no sudo-PATH gotcha). Reads the nanodep
  # basic-auth key from $NANODEP_API (the systemd unit's EnvironmentFile = the
  # sops-rendered nanodep.env, same key the container uses). Talks to nanodep on
  # localhost:9002 exactly like the proven manual sweep.
  depAutoAssign = pkgs.writeShellApplication {
    name = "dep-autoassign";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = ''
      # Fetch every device Apple has assigned to THIS MDM server (the "${depName}"
      # DEP OAuth token only sees our own devices — so this can never touch
      # another server's fleet), paginate on more_to_follow, and PUT the
      # enrollment profile onto any whose profile_status is "empty".
      #
      # Idempotent + conservative: we assign ONLY to "empty" devices, never to
      # ones already "assigned"/"pushed" (a re-PUT would reset a provisioned Mac's
      # status and could trigger an unwanted re-push) nor "removed" (intentional).
      API="http://127.0.0.1:9002"
      DEP="${depName}"
      PROFILE="${depProfileUUID}"
      : "''${NANODEP_API:?NANODEP_API must be set (nanodep.env)}"

      req() {
        curl -fsS --max-time 30 -u "depserver:''${NANODEP_API}" \
          -H 'Content-Type: application/json' "$@"
      }

      cursor="" ; scanned=0 ; found=0 ; assigned=0 ; failed=0
      while : ; do
        if [ -z "$cursor" ]; then body='{"limit":100}'
        else body="$(jq -cn --arg c "$cursor" '{limit:100,cursor:$c}')" ; fi
        resp="$(req -X POST "$API/proxy/$DEP/server/devices" -d "$body")"

        scanned=$(( scanned + $(jq '.devices | length' <<<"$resp") ))
        empties="$(jq -r '.devices[] | select(.profile_status=="empty") | .serial_number' <<<"$resp")"

        if [ -n "$empties" ]; then
          devs="$(jq -R . <<<"$empties" | jq -cs .)"
          found=$(( found + $(jq 'length' <<<"$devs") ))
          payload="$(jq -cn --arg p "$PROFILE" --argjson d "$devs" '{profile_uuid:$p, devices:$d}')"
          result="$(req -X PUT "$API/proxy/$DEP/profile/devices" -d "$payload")"
          assigned=$(( assigned + $(jq '[.devices[] | select(. == "SUCCESS")] | length' <<<"$result") ))
          bad=$(jq '[.devices[] | select(. != "SUCCESS")] | length' <<<"$result")
          failed=$(( failed + bad ))
          if [ "$bad" -gt 0 ]; then
            jq -r '.devices | to_entries[] | select(.value != "SUCCESS") | "  assign FAILED \(.key): \(.value)"' <<<"$result"
          fi
        fi

        [ "$(jq -r '.more_to_follow' <<<"$resp")" = "true" ] || break
        cursor="$(jq -r '.cursor // ""' <<<"$resp")"
      done

      if [ "$found" -eq 0 ]; then
        echo "dep-autoassign: scanned $scanned device(s), none empty — nothing to do"
      else
        echo "dep-autoassign: scanned $scanned, $found empty → assigned $assigned, failed $failed (profile $PROFILE)"
      fi
      [ "$failed" -eq 0 ]
    '';
  };
in
{
  # The nanomdm/scep/nanodep release binaries are linux-amd64 (fetched by
  # fetchRelease). vista is an Intel T2 MacBook (x86_64) so this holds; the
  # assert guards against a future ARM host silently building unrunnable images.
  assertions = [{
    assertion = pkgs.stdenv.hostPlatform.isx86_64;
    message = "hosts/vista/mdm.nix ships linux-amd64 MDM binaries; host must be x86_64.";
  }];

  # ── Secrets ────────────────────────────────────────────────────────────────
  # scep_challenge lives in secrets/mantle.yaml (add *vista to its .sops.yaml
  # rule + `sops updatekeys`). nanomdm_api is NOT redeclared here — vista already
  # declares it (from vista-deus.yaml) in hosts/vista/secrets.nix, and both deus
  # and nanomdm read that same value, so they match by construction.
  sops.secrets.scep_challenge.sopsFile = ../../secrets/mantle.yaml;

  sops.templates."nanomdm.env" = {
    restartUnits = [ "docker-nanomdm.service" ];
    content = "NANOMDM_API=${config.sops.placeholder.nanomdm_api}\n";
  };
  sops.templates."scep.env" = {
    # the enroll server renders the same SCEP_CHALLENGE into its profile.
    restartUnits = [ "docker-scep.service" "docker-mdmenroll.service" ];
    content = "SCEP_CHALLENGE=${config.sops.placeholder.scep_challenge}\n";
  };
  # nanodep reuses the nanomdm API key for its operator API (both are internal/localhost).
  sops.templates."nanodep.env" = {
    restartUnits = [ "docker-nanodep.service" ];
    content = "NANODEP_API=${config.sops.placeholder.nanomdm_api}\n";
  };

  # ── Persistent data dirs (data pool; one parent for easy backup/move) ───────
  # Both containers run as root; the scep depot is 0755 so nanomdm can read ca.pem
  # (ca.key stays 0600, written by scepserver, so the CA private key is protected).
  systemd.tmpfiles.rules = [
    "d ${dataDir}          0755 root root -"
    "d ${dataDir}/nanomdm  0700 root root -"
    "d ${dataDir}/scep     0755 root root -"
    "d ${dataDir}/nanodep  0700 root root -"
  ];

  # ── scep (CA) container ────────────────────────────────────────────────────
  virtualisation.oci-containers.containers.scep = {
    imageFile = scepImage;
    image = "malli-scep:2.3.0";
    ports = [ "10.100.0.4:${toString scepHostPort}:8080" ];
    volumes = [ "${dataDir}/scep:/depot" ];
    environmentFiles = [ config.sops.templates."scep.env".path ]; # SCEP_CHALLENGE
  };

  # ── nanomdm (MDM server) container ─────────────────────────────────────────
  virtualisation.oci-containers.containers.nanomdm = {
    imageFile = nanomdmImage;
    image = "malli-nanomdm:0.6.0";
    # Bind all interfaces (was 127.0.0.1-only): the cloudflared tunnel
    # still reaches it on localhost (mdm.matv.io → localhost:9990), and
    # deus-server on conduit can now reach the enqueue API over WireGuard
    # at 10.100.0.2:9990. wg0 is firewall-trusted and harbor has no public
    # inbound IP (behind a NAT we don't control), so this doesn't widen
    # internet exposure — same posture as the immich/jellyfin containers.
    ports = [ "10.100.0.4:${toString nanomdmHostPort}:9000" ];
    volumes = [
      "${dataDir}/nanomdm:/app/db"       # file-backend store (devices, queue, push cert)
      "${dataDir}/scep:/app/scep:ro"     # read the SCEP CA cert to validate device certs
    ];
    environmentFiles = [ config.sops.templates."nanomdm.env".path ]; # NANOMDM_API
  };

  # nanomdm needs the SCEP CA cert (ca.pem) to exist first — scep's entrypoint creates it.
  # On mantle the containers bind to the WireGuard IP 10.100.0.4, so wg0 must be
  # up before they start (harbor binds 0.0.0.0/127.0.0.1 so needs no such dep).
  systemd.services.docker-nanomdm = {
    after = [ "docker-scep.service" "docker-networks.service" "wg-quick-wg0.service" ];
    requires = [ "docker-scep.service" "wg-quick-wg0.service" ];
  };
  systemd.services.docker-scep = {
    after = [ "docker-networks.service" "wg-quick-wg0.service" ];
    requires = [ "wg-quick-wg0.service" ];
  };
  systemd.services.docker-mdmenroll = {
    after = [ "docker-networks.service" "wg-quick-wg0.service" ];
    requires = [ "wg-quick-wg0.service" ];
  };

  # ── nanodep (ABM/ADE connector) container ──────────────────────────────────
  # Operator/deus-facing only (talks OUTBOUND to Apple's DEP API), so bound to
  # localhost — no cloudflared tunnel needed.
  virtualisation.oci-containers.containers.nanodep = {
    imageFile = nanodepImage;
    image = "malli-nanodep:0.7.0";
    ports = [ "127.0.0.1:9002:9001" ]; # 9001 taken on harbor; map to 9002
    volumes = [ "${dataDir}/nanodep:/app/db" ];
    environmentFiles = [ config.sops.templates."nanodep.env".path ]; # NANODEP_API
  };
  systemd.services.docker-nanodep.after = [ "docker-networks.service" ];

  # ── ADE enrollment-profile server container ────────────────────────────────
  # Serves the static enrollment .mobileconfig at the DEP profile's `url`
  # (https://enroll.matv.io/enroll via the tunnel — see access.nix). Stateless;
  # no volumes. Needs SCEP_CHALLENGE to render the SCEP payload at startup.
  virtualisation.oci-containers.containers.mdmenroll = {
    imageFile = enrollImage;
    image = "malli-mdmenroll:1.0.0";
    ports = [ "10.100.0.4:9991:8080" ]; # 9990 is nanomdm; 9991 is free
    environmentFiles = [ config.sops.templates."scep.env".path ]; # SCEP_CHALLENGE
  };

  # ── DEP auto-assigner service + timer ──────────────────────────────────────
  # Runs the depAutoAssign script every ~5 min so any Mac newly added to ABM
  # gets the enrollment profile without a manual sweep. NANODEP_API comes from
  # the same sops-rendered env the nanodep container reads (systemd, not the
  # sandboxed process, loads EnvironmentFile — so ProtectSystem is fine).
  systemd.services.dep-autoassign = {
    description = "Assign the fleet DEP enrollment profile to empty ABM devices";
    after = [ "docker-nanodep.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${depAutoAssign}/bin/dep-autoassign";
      EnvironmentFile = config.sops.templates."nanodep.env".path;
      # localhost HTTP + read one env file, write nothing — box it in.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  systemd.timers.dep-autoassign = {
    description = "Periodically assign the DEP profile to empty ABM devices";
    wantedBy = lib.mkForce [ ]; # S1: DISABLED until S4 cutover (mantle sole assigner)
    timerConfig = {
      OnBootSec = "3min";        # let docker-nanodep settle after a reboot
      OnUnitActiveSec = "5min";
    };
  };
}
