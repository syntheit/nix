# Vista MDM credential migration — offline, default-off draft

`malli.mdm.privateCredentials.prepare`, `malli.mdm.privateCredentials.enable`,
`malli.mdm.deusDedicatedIdentity.enable`,
and `malli.mdm.ddmBridge.enable` all default to `false`. This draft does not
change the running Vista stack or authorize a deployment. The existing v0.6
NanoMDM, shared NanoDEP key, query-string webhook, and 0444 token staging
remain the default. No new key value or published patched-source pin is in this
repository. The current `deus` flake lock also predates its HMAC receiver; an
opt-in eval against that lock correctly fails. The reviewed Deus revision must
be published and pinned before a production cutover.

## What the opt-in configuration does

With verified prerequisites, it selects an immutable patched NanoMDM v0.9
source pin, keeps the existing file store (`enable_deprecated=1`), uses
`-api-key-file` and `-webhook-hmac-key-file` with root-owned 0600 files, and
uses a webhook URL with **no** token query. The patched NanoMDM key-file
contract uses exact file bytes. The staging helper rejects CR/LF and other
whitespace instead of guessing how to transform the legacy key. It verifies
that the API, HMAC, and new NanoDEP keys differ before staging anything. The
HMAC key must be 32–256 printable ASCII bytes. It stages private copies for
NanoMDM root and the nspawn Deus UID/GID 3999, then atomically replaces the
old `/var/lib/deus-tokens/nanomdm-api` 0444 file with a 0600 UID-3999 copy.
The default-off path still stages that old file exactly as before.

NanoDEP receives a **distinct** secret in its existing environment template,
including its auto-assigner. NanoDEP v0.7 still puts *its own* API key in
process argv. This draft therefore prevents continued exposure of the
NanoMDM key through NanoDEP, but it does **not** make NanoDEP's credential
private. Do not mark `ddmBridge.credentialMigrationConfirmed` true on the
strength of this MDM cutover.

The UID-3999 identity option is separate from the bridge. It creates a
dedicated host identity and switches the nspawn Deus UID only after an explicit
operator attestation. It never auto-chowns `/var/lib/deus` or starts the DDM
bridge. The bridge independently requires its existing full-credential and
private-receiver gates. Existing operator, agent, service, fleet-age, and
Cloudflare granter credentials are still staged 0444 under traversable host
directories; they require a separate audit and coordinated rotation. Host UID
999 currently collides with `btrbk`, so merely changing a socket's mode or
adding HMAC files without migrating the entire Deus state is not sufficient.
The private Deus copies are under `/var/lib/deus-tokens/private-mdm`, in the
**existing** read-only nspawn bind mount. No new mount or nspawn restart is
needed merely to expose this credential directory; the UID change itself
still requires its own approved state migration and service validation.

## Prerequisites and sequence (operator-approved maintenance window)

1. Publish and pin the reviewed patched NanoMDM v0.9 revision with real
   source and Go vendor hashes. Verify an offline v0.6→v0.9 file-backend
   restore, APNs certificate/topic, enrollments, and ADE check-ins from a
   protected backup. Do not set `-dm` or send `DeclarativeManagement`.
2. Deploy a reviewed Deus release that can **accept both legacy-only and
   HMAC-only** ADE webhooks while still configured for legacy-only traffic.
   HMAC plus `?token=` in the *same request* is not a transition mode: Deus
   rejects any signed request carrying a query string. Do not configure both
   on NanoMDM.
3. Create two *separate* sops-encrypted binary files: a random >=32-byte
   printable ASCII webhook HMAC key and a distinct NanoDEP API key. Use a
   generator that writes no trailing newline. Set `hmacSopsFile` and
   `nanodepSopsFile` to those encrypted file paths; never embed their values
   in Nix. Verify the existing NanoMDM API key's exact source bytes against
   the old API using an authenticated request that prints neither key nor
   request headers. Do not use `curl -u user:<key>` or an Authorization header
   literal in argv; use a tiny client that reads the protected file internally
   and reports only the HTTP status. Set `apiKeyVerified` only after the probe
   succeeds.
4. Back up and audit the **entire** nspawn Deus state/bind-mount tree. In a
   separately approved window, migrate only entries owned by the old Deus
   UID/GID 999 to 3999:3999, preserve all unrelated owners, verify nspawn and
   Docker kernel UID maps, and check `/var/lib/deus` is 3999:3999 mode 0700.
   Enable `deusDedicatedIdentity` only after that check; it does not migrate
   state. The host activation and nspawn start preflights enforce the parent
   ownership/mode before the container starts. The reviewed Deus module's
   inner tmpfiles rule still enforces parent 3999:3999 mode 0700, but does not
   recursively migrate contents; the whole tree must be audited first. A
   failed state check means restore the backup and stop.
5. Deploy a **first generation** with `privateCredentials.prepare = true`,
   `receiverVerified = true`, both encrypted secret-file paths set, and
   `enable = false`. This stages private files, resecures the old 0444 API
   copy, points Deus at the new API/HMAC files, and lets Deus accept both
   legacy-only and HMAC-only webhooks. NanoMDM itself stays v0.6, still sends
   only legacy webhooks, and keeps its current env/mounts. Check ownership,
   exact-byte Basic API auth, ADE check-ins, NanoDEP autoassigner, and the
   receiver's signed-test path. A missing HMAC source makes Deus's
   `LoadCredential` fail its **whole unit** start; do not restart it before
   staging and checking those files. Set `prepareDeployedAndVerified = true`
   only after this generation is healthy.
6. Deploy a **second generation** with `privateCredentials.enable = true`,
   `apiKeyVerified = true`, and a real patched v0.9 source pin. Keep
   `retireLegacyWebhook = false`: Deus accepts both methods while NanoMDM
   switches to the secret-free HMAC-only webhook URL. Verify signed fleet
   inventory, NanoMDM Basic API, APNs push, MDM enrollment/check-in, and
   public MDM/ADE availability. Only after observing HMAC-only production
   traffic, set `hmacTrafficVerified = true` and
   `retireLegacyWebhook = true` in a **third** receiver-only generation.
   NanoMDM and Deus read keys at startup; changing staged files alone does
   not rotate in-memory keys.

This is a coordinated service cutover, not a zero-downtime promise. A failed
activation may leave a partial system generation; stop, inspect both service
PIDs and health, and restore the prior generation with matching secrets before
restarting either service. The staging operation is idempotent once the cause
is fixed, but its partial failure must never be treated as a successful
cutover.
Do not enable the bridge as part of this step. The bridge still needs its own
independent HMAC keys, trusted command-receipt path, 5fro enrollment pin, and
full credential-migration attestation.

## Declarative management (`-dm`), separately default-off

`malli.mdm.declarativeManagement.enable` is a **fourth** switch, off by
default and off in every step above. It adds `-dm http://127.0.0.1:9992/`
plus `-dm-send-hmac-key-file` and `-dm-recv-hmac-key-file` to the patched
NanoMDM entrypoint. The URL keeps its **trailing slash**: NanoMDM resolves
the device-supplied endpoint against this prefix with Go's relative path
resolver, which drops the last path element of a prefix that lacks one.
The destination is the bridge sidecar inside NanoMDM's own network
namespace, so it is never a host port. The endpoint and the bridge's listen
tuple are **built from one host string and one port**, so they cannot drift
apart. (An earlier revision of this document claimed an assertion tied them.
It did not: only the bridge `.py` was checked, so editing the endpoint URL
alone left every assertion green. The tie is structural now, and the
evaluation test takes the address back apart and checks it against
`packages/nanomdm-ddm-bridge.py`.)

### The pin is not the gate: the reviewed-source allowlist

A source pin on its own constrains nothing: vendoring **stock upstream v0.9**
into Deus and pinning its hash would build the server whose `-dm` resolves a
device-supplied endpoint and forwards the enrollment headers with it, i.e. the
server-side request-forgery primitive, live against the whole enrolled fleet.
The patched server's only source is Deus's vendored `third_party/nanomdm`,
and evaluation fails unless the locked `deus` input carries exactly the tree
the pin's NAR hash names. `declarativeManagement.enable` additionally requires
the pin's Deus revision, vendored commit and hash to appear together in one
row of
[`hosts/vista/nanomdm-reviewed-source.nix`](../hosts/vista/nanomdm-reviewed-source.nix),
and refuses the stock v0.9.0 tree outright whatever that allowlist says. The
bridge re-checks the same allowlist, and separately requires the image tag
the container will actually run to be one built from an allowlisted
row — it no longer reads a name it derived from the pin it was supposed to be
checking.

The allowlist holds one row: the Deus revision that vendors the canary tree
`3c52ba4`. Because the hash is what is enforced, a later Deus revision that
leaves `third_party/nanomdm` untouched needs no new row. Adding one is a
security review — read the vendored tree's diff against upstream, confirm the
confinement has no escape, confirm the row's hash is that tree, build it, run
the canary against one verified enrollment, then record it with the date and
the reviewer.

Beyond the pin it requires `privateCredentials.enable` (the key files are
staged and mounted only on that path), `ddmBridge.enable`, and **three** more
separately encrypted binary secret files — `sendHmacSopsFile`,
`recvHmacSopsFile` and `receiptHmacSopsFile`, each an independently generated
32–256 byte printable ASCII key with no trailing newline, distinct from each
other and from the API, webhook and NanoDEP keys. The staging helper refuses
a half-configured set and any reuse. NanoMDM's *send* key is what Deus
verifies as its DDM *request* key; NanoMDM's *receive* key is the one Deus
*signs responses* with.

The **third, receipt key is required, not optional**, even though the pinned
NanoMDM build has no command-receipt sender. The pinned Deus module emits
`-ddm-receipt-key-file %d/ddm-receipt-hmac` unconditionally whenever
`ddm.enable`: that path is non-empty, so `readDDMKey` fails with `ENOENT`,
`configurePrivateDDM` errors, and `configureOptionalPrivateDDM` disables the
**entire** private listener. The socket is then never created, the bridge
preflight's `test -S` fails, and the sidecar never starts — leaving the key
out did not skip receipts, it meant the opt-in path could not start at all.
The cleaner long-term fix is for Deus to omit the flag when no receipt key
is configured; that change belongs in the Deus repo and is not made here.

`ddmBridge.enable` now also creates `/var/lib/deus/ddm-private` (UID 3999,
mode 0700) — the one directory Deus requires to exist before it will bind
its private listener, and which it never creates itself — pins the Deus
listener to `ddmBridge.enrollmentID`, and copies all three staged keys into
the container's `/run/credstore` so systemd's bare `LoadCredential` names
resolve. Each copy is preceded by an `r` line removing the destination,
because tmpfiles' `C+` does **not** overwrite an existing file; see
Rotation below. The container reload is ordered after
`vista-mdm-stage-credentials`, so the first DDM enablement cannot copy from
sources that activation has not written yet. Nothing here generates or
commits key material.

## Rotation and rollback

The initial migration deliberately preserves the current NanoMDM API key for
continuity. That key may already have appeared in old process arguments,
Docker metadata, logs, or snapshots. After HMAC-only health is proven, rotate
it as a **separate** operation using Deus's reviewed 401-only secondary-key
rollover, with no retry of ambiguous POST/transport failures. Rotate NanoDEP's
distinct key independently; patch NanoDEP for a private key file before
claiming its argv exposure is fixed. Rotate operator/agent/service and other
0444 staged credentials separately before the bridge's
`credentialMigrationConfirmed` can be true.

For an HMAC rotation, stage the new key for both services, validate mode and
identity, restart the receiver first and sender second in one maintenance
window, then verify signed check-ins. Do not rely on sops file updates alone:
Docker bind mounts and systemd `LoadCredential` snapshot/startup behavior mean
running processes can continue with old keys. A mismatch may cause webhook
rejections even though both services appear started.

The DDM credstore has a specific version of that trap. `systemd-tmpfiles`'
`C+` copies only when the destination does **not** exist (verified on systemd
261), so after a sops rotation plus a `switch` that merely *reloads* the
container, NanoMDM picks up the new key while Deus keeps serving the
boot-time copy — HMAC verification then fails silently, with both services
"started" and a `systemctl restart deus-server` making no difference, since
the stale bytes are in `/run/credstore`, not in the unit. Each `C+` is
therefore preceded by `r /run/credstore/ddm-…-hmac`, which removes the stale
copy so the copy actually happens. That fixes the *copy*, not the process: a
running Deus has already read its credentials, so the restart-receiver-first
window above still applies.

For rollback before a first DDM command, restore the previously tested Nix
generation, *its matching secret values*, and the protected NanoMDM file-store
backup if v0.9 altered data. The old v0.6 generation will restage the API key
0444 and expose it again in argv/query, so rollback is a security regression
and must be time-limited and followed by rotation. Rolling back the UID change
also requires the separately approved state backup/ownership reversal; do not
blindly `chown -R`. Never revert an already-sent first DDM command assuming
it disables DDM for that enrollment.

Offline checks only:

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest packages/test_vista_mdm_stage_credentials.py
nix eval --impure --offline --json \
  --override-input deus 'git+file:///path/to/malli-deus?rev=<reviewed revision>' \
  --apply 'vista: import ./tests/vista-mdm-credentials-eval.nix { inherit vista; }' \
  .#nixosConfigurations.vista
```

The `deus` override must be a committed Deus revision that vendors the
reviewed `third_party/nanomdm`: the test pins the shipped allowlist row, and
evaluation refuses a pin whose hash is not the tree that input carries. The
test uses that pin, fake hashes in its negative cases, and existing encrypted
files as **evaluation fixtures only**. It never builds anything or decrypts
those files; do not deploy its configuration.
