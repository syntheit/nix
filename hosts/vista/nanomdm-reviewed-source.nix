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
# A source pin on its own proves NOTHING about that: `owner = "micromdm"` is
# just as pinnable as the fork, and it yields exactly the exploitable build.
# So malli.mdm.declarativeManagement.enable refuses to evaluate unless the
# configured pin's owner, repo AND full 40-hex revision appear below.
#
# ADDING A ROW HERE IS A SECURITY REVIEW, NOT A VERSION BUMP:
#   1. read that revision's diff against upstream and confirm the endpoint
#      confinement is present, total, and has no escape for absolute or
#      root-relative device-supplied endpoints;
#   2. build it and run the DDM canary against one verified enrollment;
#   3. add the full 40-character revision below with the date, the reviewer,
#      and the canary result.
#
# `revisions` is EMPTY ON PURPOSE. The endpoint-confined fork is not published
# yet (docs/nanomdm-v09-packaging-draft.md), so no revision has been reviewed
# and `-dm` cannot be enabled at all — which is the correct state, not a gap.
# ─────────────────────────────────────────────────────────────────────────────
{
  # Where the endpoint-confined fork will be published. Confirm this is
  # actually where it landed before adding the first revision below; a
  # revision is only meaningful together with the owner/repo it belongs to.
  owner = "NRE-Product";
  repo = "nanomdm";

  revisions = [
    # "0123456789abcdef0123456789abcdef01234567"  # YYYY-MM-DD, reviewed by …,
    #                                             # canary: … on m-XXXX
  ];

  # Sources that can NEVER be allowlisted, whatever else is written above or
  # overridden in a host configuration: these publish the unpatched build whose
  # `-dm` endpoint resolution is the request-forgery primitive this gate exists
  # for. Pinning one of them is the single most likely way to arrive at a fully
  # "passing" evaluation that ships the vulnerability.
  deniedOwners = [ "micromdm" "jessepeterson" ];
}
