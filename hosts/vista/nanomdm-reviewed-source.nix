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
# third_party/nanomdm, read from this flake's `deus` input. Each row below is
# the owner's sign-off for one Deus revision whose vendored tree was reviewed,
# with that tree's NAR hash, the reviewer, the date, and a one-line reason.
# malli.mdm.declarativeManagement.enable refuses to evaluate unless the
# configured pin's deusRev, nanomdmCommit AND hash appear together in one
# row, and mdm.nix separately refuses a pin whose hash is not the NAR hash of
# the tree the locked `deus` input actually carries. So the hash is what is
# enforced: a later Deus revision that leaves third_party/nanomdm untouched
# carries the same tree hash and stays covered by the existing row. deusRev is
# NOT checked against the locked `deus` input; it records which revision the
# owner reviewed. A revision that changes the tree cannot reach -dm until its
# build is reviewed and a new row is added here.
#
# ADDING A ROW HERE IS THE OWNER'S SECURITY SIGN-OFF, NOT A VERSION BUMP.
# Before adding it, confirm that the vendored tree builds byte-identically to
# the reviewed canary NanoMDM commit 3c52ba4a031c6d2035cea0722a47c598318fc59d,
# whose reviewed output is
# /nix/store/301070qz9p20r0pvpv124b0qgdbn2a6r-nanomdm-0.9.0-patched-3c52ba4a031c.
# Record the owner/reviewer, date, and one-line reason in the row. This sign-off
# deliberately happens at the start of the on-device session: the DDM canary
# requires -dm, and -dm requires this row. After the session, append the
# on-device canary result to that row as a comment; it is not a prerequisite.
#
# Example only (do not uncomment without the owner's sign-off):
# {
#   deusRev = "101d427b9c879be013d201269608bc5f3ef00494";
#   nanomdmCommit = "3c52ba4a031c6d2035cea0722a47c598318fc59d";
#   hash = "sha256-lhhXPgBp7SmdMCQc1c9/3ZBmrAbElvdXDtEWN68BP/Y=";
#   reviewer = "Owner Name";
#   reviewDate = "YYYY-MM-DD";
#   reason = "Vendored build is byte-identical to the reviewed canary.";
#   # On-device canary result (append after the session): ...
# }
# ─────────────────────────────────────────────────────────────────────────────
{
  # M2 5fro DDM canary: status 26.3 / 25D125 / J773gAP; max(error_count)=0; see ~/m2-5fro/step6-6g.ok.
  revisions = [ { deusRev = "d8ee3f2f7b50e97d0f9cda20cfef35a3ad995a1a"; nanomdmCommit = "3c52ba4a031c6d2035cea0722a47c598318fc59d";
    hash = "sha256-lhhXPgBp7SmdMCQc1c9/3ZBmrAbElvdXDtEWN68BP/Y="; reviewer = "Daniel Miller"; reviewDate = "2026-09-24";
    reason = "Vendored tree is the reviewed canary 3c52ba4 (git tree db41e28); -dm endpoint confinement reviewed."; } ];

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
