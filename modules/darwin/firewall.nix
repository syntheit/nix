{
  config,
  lib,
  ...
}:

# The application firewall (stealth mode, common.nix) drops inbound traffic to
# unknown binaries, and nix-darwin has no per-app allow option. Nix store
# binaries are unsigned, so anything that listens (mosh-server, roc-recv) has
# to be allowed explicitly; each rebuild allows the current store path and
# removes entries for older paths of the same binary.
let
  cfg = config.matv.darwin.firewallAllowedApps;
in
{
  options.matv.darwin.firewallAllowedApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = lib.literalExpression ''[ "''${pkgs.mosh}/bin/mosh-server" ]'';
    description = "Store-path executables allowed through the macOS application firewall.";
  };

  config = lib.mkIf (cfg != [ ]) {
    system.activationScripts.postActivation.text = lib.mkAfter ''
      fw=/usr/libexec/ApplicationFirewall/socketfilterfw
      ${lib.concatMapStrings (app: ''
        $fw --listapps | sed -n 's|^[0-9]* : \(/nix/store/[^ ]*/${baseNameOf app}\) *$|\1|p' | while read -r old; do
          [ "$old" = "${app}" ] || $fw --remove "$old" >/dev/null
        done
        $fw --add ${app} >/dev/null
        $fw --unblockapp ${app} >/dev/null
      '') cfg}
    '';
  };
}
