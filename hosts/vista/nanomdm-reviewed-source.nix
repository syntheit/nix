# ─────────────────────────────────────────────────────────────────────────────
# REVIEWED PATCHED-NANOMDM SOURCES — a security allowlist, not a version file.
#
# `-dm` is only safe on a build whose declarative-management endpoint is
# confined to Apple's relative DDM forms. Stock NanoMDM v0.9 resolves the
# DEVICE-SUPPLIED endpoint against the configured prefix and forwards the
# enrollment headers with it, which makes the MDM server a request-forgery
# proxy onto anything its network namespace can reach — with ~535 enrolled
# Macs able to aim it.
#
# The patched server has exactly one source: the tree Deus vendors at
# third_party/nanomdm, read from this flake's `deus` input. Each row below is a
# Deus revision whose vendored tree was reviewed, with that tree's NAR hash.
# malli.mdm.declarativeManagement.enable refuses to evaluate unless the
# configured pin's deusRev, nanomdmCommit AND hash appear together in one
# row, and mdm.nix separately refuses a pin whose hash is not the NAR hash of
# the tree the locked `deus` input actually carries. So the hash is what is
# enforced: a later Deus revision that leaves third_party/nanomdm untouched
# builds the same server and needs no new row, and one that changes it cannot
# reach -dm until it is reviewed and added here.
#
# ADDING A ROW HERE IS A SECURITY REVIEW, NOT A VERSION BUMP:
#   1. read the vendored tree's diff against upstream and confirm the endpoint
#      confinement is present, total, and has no escape for absolute or
#      root-relative device-supplied endpoints;
#   2. confirm the row names that tree: `git rev-parse <deusRev>:third_party/nanomdm`
#      is the reviewed tree, and `nix hash path third_party/nanomdm` at
#      <deusRev> is `hash`;
#   3. build it and run the DDM canary against one verified enrollment;
#   4. add the row with the date, the reviewer, and the canary result.
# ─────────────────────────────────────────────────────────────────────────────
{
  revisions = [
    {
      # 2026-09-21. Vendored by `git subtree add` from NanoMDM
      # canary/v0.9.0-dm-minimal (upstream v0.9.0 plus the endpoint
      # confinement f8ec94f, the DM key files de59483 and the API/webhook key
      # files 99ea1e8 and af56aee). third_party/nanomdm is git tree
      # db41e28498eb7ee08c0a48c66a4aac034a59f3ab, identical to the canary's,
      # and with this flake's nixpkgs it builds the reviewed canary derivation
      # byte for byte. On-device DDM canary: not recorded yet.
      deusRev = "101d427b9c879be013d201269608bc5f3ef00494";
      nanomdmCommit = "3c52ba4a031c6d2035cea0722a47c598318fc59d";
      hash = "sha256-lhhXPgBp7SmdMCQc1c9/3ZBmrAbElvdXDtEWN68BP/Y=";
    }
  ];

  # Trees that can NEVER be allowlisted, whatever else is written above or
  # overridden in a host configuration: stock upstream, whose `-dm` endpoint
  # resolution is the request-forgery primitive this gate exists for.
  # Re-vendoring the upstream release instead of the patched canary is the
  # single most likely way to arrive at a fully "passing" evaluation that
  # ships the vulnerability, so it is refused by both its commit and its NAR
  # hash (`git archive 54b9eaf | tar -x` then `nix hash path`).
  denied = [
    {
      what = "micromdm/nanomdm v0.9.0, unpatched";
      nanomdmCommit = "54b9eaf13b03e5f5b64965469964717347660fa5";
      hash = "sha256-XngjhSX8GW9Qx4ggsQVLREfDyA2D2rIUqiPI8NqUfj0=";
    }
  ];
}
