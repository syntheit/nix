# TCC.db grants (requires SIP disabled) and the screen recording reminders.
#
# This runs at the start of postActivation, before home-manager: a failing
# home-manager step (codesign with a locked keychain, 2026-10-22) used to
# abort the whole activation before the grants were written, and yabai, skhd
# and sunshine lost their permissions. Every command here only warns.
#
# csrutil disable puts Apple Silicon in Permissive Security, which leaves the
# OS "Not Paired" (bputil -d), and macOS OTA updates then fail at preflight
# with "Failed to personalize" (MSU error 1259). macOS update runbook:
#   1. recovery -> csrutil enable (needs Wi-Fi) -> reboot
#   2. install the macOS update
#   3. recovery -> csrutil disable -> reboot
#   4. darwin-rebuild switch (re-applies these grants)
{
  pkgs,
  lib,
  vars,
  config,
  ...
}:

let
  grants = config.matv.darwin.tccGrants;

  # Path entries match the resolved executable (client_type 1) and need a new
  # row for every new store path. Bundle entries match the bundle id plus a
  # code requirement compiled here (client_type 0), so they hold across
  # rebuilds while the app stays signed with the same identity.
  grantScript =
    g:
    if g ? bundleId then
      ''
        # ${g.reason}
        req="$(mktemp)"
        if printf '%s' ${lib.escapeShellArg g.requirement} | /usr/bin/csreq -r- -b "$req" \
          && csreq_hex="$(od -An -v -tx1 "$req" | tr -d ' \n')" && [ -n "$csreq_hex" ]; then
          sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq) VALUES ('${g.service}', '${g.bundleId}', 0, 2, 4, 1, X'$csreq_hex');" \
            || echo "warning: TCC grant ${g.service} for ${g.bundleId} failed" >&2
        else
          echo "warning: cannot compile the code requirement for ${g.bundleId}; skipped its ${g.service} grant" >&2
        fi
        rm -f "$req"
      ''
    else
      ''
        # ${g.reason}
        sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('${g.service}', '$(readlink -f ${g.package}/bin/${g.exec})', 1, 2, 4, 1);" \
          || echo "warning: TCC grant ${g.service} for ${g.exec} failed" >&2
      '';

  # macOS nags every 30 days that an app "has been accessing your screen"
  # (kScreenCapturePrivacyHintPolicy = 2592000), per executable path, from
  # replayd's approvals file. Each screen capture grant gets a fresh entry
  # whose next reminder is in 2100. Runs as the user, who owns the file.
  screenCaptureExecs = map (g: "$(readlink -f ${g.package}/bin/${g.exec})") (
    lib.filter (g: g.service == "kTCCServiceScreenCapture" && g ? package) grants
  );
  approveScreenCapture = pkgs.writeShellScript "approve-screen-capture" ''
    pb=/usr/libexec/PlistBuddy
    f=${lib.escapeShellArg "/Users/${vars.user.name}/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist"}
    mkdir -p "$(dirname "$f")" || exit 1
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    # PlistBuddy can't parse dates on the command line, so the entry is merged
    # from an XML fragment.
    frag="$(mktemp)" || exit 1
    trap 'rm -f "$frag"' EXIT
    cat > "$frag" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>kScreenCaptureApprovalLastAlerted</key><date>$now</date>
    <key>kScreenCaptureApprovalLastUsed</key><date>$now</date>
    <key>kScreenCapturePrivacyHintDate</key><date>2100-01-01T00:00:00Z</date>
    <key>kScreenCapturePrivacyHintPolicy</key><integer>2592000</integer>
    </dict></plist>
    EOF
    rc=0
    for exe in "$@"; do
      [ -n "$exe" ] || continue
      $pb -c "Delete :'$exe'" "$f" >/dev/null 2>&1 || true
      if ! $pb -c "Add :'$exe' dict" -c "Merge $frag :'$exe'" "$f" >/dev/null; then
        echo "warning: no screen capture approval for $exe" >&2
        rc=1
      fi
    done
    # PlistBuddy saves XML; replayd writes binary.
    plutil -convert binary1 "$f" >/dev/null 2>&1 || true
    chgrp staff "$f" || rc=1
    chmod 600 "$f" || rc=1
    exit $rc
  '';
in
{
  options.matv.darwin.tccGrants = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
    default = [ ];
    description = ''
      TCC.db grants written at the start of postActivation, before
      home-manager. Each entry has service and reason, plus either
      package/exec (a store binary, matched by its resolved path) or
      bundleId/requirement (a signed app, matched by bundle id and a code
      requirement such as `identifier "x" and anchor apple generic and
      certificate leaf[subject.OU] = "TEAMID"`). Hosts populate this from
      modules/darwin/tcc-grants.nix and their own modules.
    '';
  };

  config.system.activationScripts.postActivation.text = lib.mkBefore ''
    # ================================================================
    # TCC permissions (requires SIP disabled), see modules/darwin/tcc.nix
    # ================================================================
    if csrutil status | grep -q 'disabled'; then
      TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
      ${lib.concatMapStringsSep "\n" grantScript grants}

      # Force tccd to reload from TCC.db: direct sqlite writes don't invalidate
      # its in-memory cache, so yabai/skhd would otherwise launch without
      # effective accessibility until tccd is restarted.
      killall tccd 2>/dev/null || true
    else
      echo "warning: SIP is enabled, skipped TCC.db grants; run 'darwin-rebuild switch' again after csrutil disable" >&2
    fi
    ${lib.optionalString (screenCaptureExecs != [ ]) ''
      sudo -u ${vars.user.name} ${approveScreenCapture} ${lib.concatMapStringsSep " " (e: ''"${e}"'') screenCaptureExecs} \
        || echo "warning: could not update the screen capture approvals" >&2
    ''}
  '';
}
