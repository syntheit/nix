# Vista private DDM bridge — implementation draft, OFF by default

`hosts/vista/ddm-bridge.nix` packages one small Python standard-library
sidecar. With `malli.mdm.ddmBridge.enable = false` (the default), it creates no
container, Docker volume, socket, secret, or UID override and leaves NanoMDM's
image and command line unchanged. This draft is **not an approval to deploy**.

When eventually enabled, Docker places the sidecar in NanoMDM's network
namespace (`--network=container:nanomdm`), with no published port. It listens
on `127.0.0.1:9992` there and forwards only these exact method/path forms to
`/run/ddm-private/socket`:

| Method | Path |
| --- | --- |
| GET | `/tokens`, `/declaration-items`, `/declaration/{activation,configuration,asset,management}/{canonical ASCII ID}` |
| PUT | `/status` |
| POST | `/v1/command-receipts` |

The only mount is `/var/lib/deus/ddm-private:/run/ddm-private:ro`; the bridge
does not receive API keys or HMAC keys. It uses direct AF_UNIX sockets, never
DNS, proxy environment variables, redirects, or public Deus HTTP. It runs as
UID/GID 3999 with no Linux capabilities, a read-only container filesystem,
no-new-privileges, strict Host/method/path/header/body limits, and 16 maximum
concurrent connections. The Deus listener must separately authenticate the
peer with `SO_PEERCRED`, pin exactly one device-channel enrollment, and verify
the original NanoMDM HMAC; the bridge is not an authentication substitute.

## Why activation is blocked

The current headscale nspawn Deus process is UID/GID 999 and shares its
host-visible UID with the host `btrbk` user. Host UID 999 can access the
read-write `/var/lib/deus` bind mount. A mode-0600 socket and `SO_PEERCRED`
cannot distinguish those two processes. Read-only checks on 2026-09-20 found
UID/GID 3999 unused on vista and inside the nspawn; both nspawn and NanoMDM
Docker have identity UID/GID maps. **Repeat those checks immediately before
any migration**; this draft does not change running identities or ownership.

Enabling the option requires all three explicit confirmations:

- `identityMigrationConfirmed`: approved backup, maintenance window, and
  ownership audit of the **entire** `/var/lib/deus` tree and any other
  Deus-owned bind-mounted state, not just the socket directory. Migrate only
  entries actually owned by the old Deus UID/GID 999; preserve root-owned and
  other identities. The new
  `/var/lib/deus` must be 3999:3999 mode 0750; create
  `/var/lib/deus/ddm-private` as 3999:3999 mode 0700. Check every file that
  Deus needs before restarting the nspawn; restore the backup and old UID
  configuration if checks fail. This module never runs `chown` or deletes a
  stale socket. The socket is created by Deus as 3999:3999 mode 0600.
- `credentialMigrationConfirmed`: remove existing world-readable staged
  Deus/NanoMDM tokens and CLI/query-string secrets via a coordinated rotation.
  Provide separate private file-backed DDM request, response, and receipt
  HMAC keys. The current NanoMDM API key and webhook token must not be
  reused as DDM keys. This draft creates no secret paths and does not change
  live credential storage.
- `receiverConfigured`: a reviewed Deus Nix module has explicitly wired the
  private listener for exactly 5fro's current device enrollment, using
  systemd `LoadCredential` (or equivalent private file-backed paths), and a
  real cross-namespace connection has proven `SO_PEERCRED` reports UID 3999.
  `-ddm-private-socket`, `-ddm-peer-uid`, `-ddm-enrollment-id`,
  `-ddm-request-key-file`, `-ddm-response-key-file`, and
  `-ddm-receipt-key-file` are needed; **these Deus module options do not yet
  exist here**. The public Deus HTTP mux must not gain DDM routes.

The Nix assertion also requires a verified `malli-nanomdm:0.9.0-patched-*`
image, with NanoMDM's device-supplied DDM endpoint confinement patch. The
current source-build pin is `null`, so enabling the bridge fails evaluation.
Before any NanoMDM `-dm` activation, add *file-backed* support for its
send/receive DDM HMAC keys; the upstream literal-key flags expose secrets in
process argv. The patched post-core receipt sender likewise needs its own
private key file. Do not set `-dm` or send the first `DeclarativeManagement`
command just to test the bridge: that command enables DDM for the enrollment.

## Lifecycle and verification

The bridge unit requires NanoMDM, but NanoMDM never requires the bridge. A
bridge failure leaves existing MDM service available. `PartOf`/`Wants` and
`After` bind the sidecar lifecycle to NanoMDM so a NanoMDM restart recreates
the sidecar in the new network namespace; otherwise it would be stranded in
the old namespace. Bridge startup checks `/var/lib/deus` ownership/mode and
requires the private directory and socket to exist with exact modes before
Docker can implicitly create a missing bind source. If Deus restarts and
replaces its socket, each request rechecks ownership/mode and reconnects by
path; during the gap requests fail with 502, never reroute to public HTTP.

Before a single-device canary, independently verify: NanoMDM v0.9 file-store
upgrade against a restored backup; bootstrap-token retrieval; current 5fro
enrollment/serial/UDID; source-pinned SSRF and key-file patches; actual
UID/GID maps, socket peer UID, loopback reachability from NanoMDM's netns,
and no host or public port published. Stop if any check differs. No retry or
new macOS update command should be inferred from a missing DDM response or
ACK receipt. Rollback of bridge traffic is disabling its option and restoring
the previous Nix generation; rollback of the UID migration requires the
separate state backup and an approved maintenance operation. Do not reverse
an already-sent first DDM command by assuming it can be disabled in place.

Offline parser tests: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest
packages/test_nanomdm_ddm_bridge.py`. These exercise an ephemeral Unix socket
and loopback only; no live MDM/Deus service is contacted.
