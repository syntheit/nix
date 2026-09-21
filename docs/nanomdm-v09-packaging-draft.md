# NanoMDM v0.9 packaging draft (not a deployment)

`hosts/vista/mdm.nix` continues to select the verified v0.6.0 release. The
opt-in `nanomdmPatchedSourcePin` is deliberately `null`.

The patched v0.9 source is vendored in Deus at `third_party/nanomdm` (see its
`third_party/VENDORED.md`), and the package builds it from this flake's
existing private `deus` input — no separate fetch, fork or deploy key, and no
local-path override. To make a deployable candidate, lock `deus` at a revision
that vendors it and set `nanomdmPatchedSourcePin` to `deusRev` (the reviewed
Deus revision), `nanomdmCommit` (the vendored canary commit), `hash` (the NAR
hash of `third_party/nanomdm`, `nix hash path`) and `vendorHash` for
`buildGoModule`. Evaluation fails unless the locked `deus` input carries exactly
the tree `hash` names, so a later Deus revision that leaves the vendored tree
alone builds the identical server, and one that changes it stops the build.
The derivation builds only `cmd/nanomdm` and runs its Go tests.
It sets `CGO_ENABLED=0` for a static binary, and the version compiled into the
binary and used as the container tag names the canary commit and the Deus
revision (`packages/nanomdm-patched/version.nix`) for rollback identity.

The draft deliberately retains the existing `/app/db` bind mount, file backend,
SCEP CA path, API key, webhook URL, APNs topic/profile, host port, and data
directory. Patched v0.9 requires `-storage-options enable_deprecated=1` with
`-storage file`; the opt-in branch adds exactly that flag and does **not**
switch to the incompatible `filekv` default. It supplies no `-dm` or
`-auth-proxy-url` flag, so the DDM endpoint remains disabled. The patched
bootstrap-token audit is metadata-only; ordinary command ACK webhooks still
contain raw plists, so this is **not** authorization to enqueue `SecurityInfo`
or use `-dump` for sensitive replies. The existing webhook token query remains
unchanged; HMAC receiver compatibility is a separate gate.

Before any cutover, verify the published commit and both hashes, perform an
offline v0.6-to-v0.9 file-backend compatibility test using a protected copy of
the store, check that APNs certificate/topic and enrollment identities survive,
exercise ADE check-ins and push delivery, and take a recoverable store backup.
In v0.9, an accepted new `Authenticate` deliberately clears the old bootstrap
token; this must be covered by the reenrollment test. Build and inspect the
container image in an isolated environment, and only then plan a separately
authorized deployment and rollback. None of those validation gates is claimed
complete by this draft.
