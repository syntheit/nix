# Unlocks the deus-signing keychain (the Developer ID identity) at the start of
# every activation, so home-manager's codesign steps (telmoSignApp,
# vestalSignApp) can sign. The keychain is normally locked and codesign then
# fails with errSecInternalComponent. Its password is the same random one
# deus-cli-release.nix reads from the login keychain; this copy lives in
# secrets/mini.yaml.
#
# set-key-partition-list lets codesign use the key without the GUI "codesign
# wants to use key" dialog. It is idempotent.
#
# Every failure only warns: a locked keychain must never stop the activation.
{
  pkgs,
  config,
  vars,
  lib,
  ...
}:

let
  user = vars.user.name;
  keychain = "/Users/${user}/Library/Keychains/deus-signing.keychain-db";
  secret = config.sops.secrets.deus_signing_keychain_password.path;

  # Runs as the user in the GUI security session. The password goes in on
  # stdin, never argv. security only reads it from stdin when there is no
  # controlling terminal (otherwise it prompts on the tty), so each call runs
  # in a new session.
  unlock = pkgs.writeShellScript "unlock-signing-keychain" ''
    kc=${lib.escapeShellArg keychain}
    pw=${lib.escapeShellArg secret}
    nosid() {
      /usr/bin/perl -MPOSIX -e 'defined(my $p = fork) or die "fork: $!\n"; if ($p) { waitpid($p, 0); exit($? & 127 ? 1 : $? >> 8) } POSIX::setsid(); exec @ARGV or die "exec: $!\n"' "$@"
    }
    # The prompt text goes to stderr; show it only on failure.
    if ! out="$(nosid /usr/bin/security unlock-keychain "$kc" < "$pw" 2>&1 >/dev/null)"; then
      echo "$out" >&2
      exit 1
    fi
    if ! out="$(nosid /usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$kc" < "$pw" 2>&1 >/dev/null)"; then
      echo "$out" >&2
      exit 2
    fi
  '';
in
{
  sops.secrets.deus_signing_keychain_password = {
    sopsFile = ../../secrets/mini.yaml;
    owner = user;
    mode = "0400";
  };

  # Before the TCC grants (mkBefore, modules/darwin/tcc.nix) and home-manager.
  system.activationScripts.postActivation.text = lib.mkOrder 400 ''
    # ================================================================
    # Unlock the deus-signing keychain (hosts/mini/signing-keychain.nix)
    # ================================================================
    # sops-nix installs secrets from its launchd daemon, which the launchd
    # step above (re)started, and again at the end of postActivation. The very
    # first activation with this secret may not have it yet.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      [ -s ${secret} ] && break
      sleep 1
    done
    if [ ! -s ${secret} ]; then
      echo "warning: ${secret} is missing; the signing keychain stays locked (codesign falls back)" >&2
    elif grep -qx PLACEHOLDER ${secret}; then
      echo "warning: deus_signing_keychain_password in secrets/mini.yaml is a placeholder; the signing keychain stays locked" >&2
    elif ! launchctl asuser "$(id -u -- ${user})" sudo -u ${user} ${unlock}; then
      echo "warning: could not unlock ${keychain}; codesign falls back" >&2
    fi
  '';
}
