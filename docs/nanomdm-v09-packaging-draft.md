# NanoMDM v0.9 packaging draft (not a deployment)

`hosts/vista/mdm.nix` continues to select the verified v0.6.0 release. The
opt-in `nanomdmPatchedSourcePin` is deliberately `null`: the patched v0.9 source
currently exists only as an unmerged local checkout, so there is no honest
remote source hash or Go vendor hash to put in the Nix configuration yet.

To make a deployable candidate, publish an immutable patched-source revision,
then set `nanomdmPatchedSourcePin` to an attribute set with `owner`, `repo`, a
full 40-character `rev`, `hash` for `fetchFromGitHub`, and `vendorHash` for
`buildGoModule`. Both hashes must be measured from that published revision and
verified by a clean Nix build; do not use a floating ref, `lib.fakeHash`, a
local `/tmp` path, or an upstream v0.9 binary lacking our patches. The
derivation builds only `cmd/nanomdm` and runs its Go tests.
It sets `CGO_ENABLED=0` for a static binary, and the opt-in container tag
includes the pinned commit's first 12 characters for rollback identity.

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
