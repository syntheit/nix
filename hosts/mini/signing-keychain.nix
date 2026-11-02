# Unlocks the deus-signing keychain (the Developer ID identity) at the start of
# every activation, so home-manager's codesign steps (telmoSignApp,
# vestalSignApp) can sign. The keychain is normally locked and codesign then
# fails with errSecInternalComponent.
#
# The password is read from ~/.config/deus-signing/keychain-pass, the same file
# deus-cli-sign-and-notarize.sh uses. The deus signing setup creates it outside
# Nix (the same dependency deus-cli-release has). If it is missing, the step
# warns and skips.
#
# set-key-partition-list lets codesign use the key without the GUI "codesign
# wants to use key" dialog. It is idempotent.
#
# Every failure only warns: a locked keychain must never stop the activation.
{
  pkgs,
  vars,
  lib,
  ...
}:

let
  user = vars.user.name;
  keychain = "/Users/${user}/Library/Keychains/deus-signing.keychain-db";
  passFile = "/Users/${user}/.config/deus-signing/keychain-pass";

  # Runs as the user in the GUI security session. The password goes in on
  # stdin, never argv. security only reads it from stdin when there is no
  # controlling terminal (otherwise it prompts on the tty), so each call runs
  # in a new session. Trailing newlines are stripped, as $(cat ...) does in
  # deus-cli-sign-and-notarize.sh.
  unlock = pkgs.writeShellScript "unlock-signing-keychain" ''
    kc=${lib.escapeShellArg keychain}
    pw="$(< ${lib.escapeShellArg passFile})" || exit 3
    nosid() {
      /usr/bin/perl -MPOSIX -e 'defined(my $p = fork) or die "fork: $!\n"; if ($p) { waitpid($p, 0); exit($? & 127 ? 1 : $? >> 8) } POSIX::setsid(); exec @ARGV or die "exec: $!\n"' "$@"
    }
    # The prompt text goes to stderr; show it only on failure.
    if ! out="$(printf '%s\n' "$pw" | nosid /usr/bin/security unlock-keychain "$kc" 2>&1 >/dev/null)"; then
      echo "$out" >&2
      exit 1
    fi
    if ! out="$(printf '%s\n' "$pw" | nosid /usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$kc" 2>&1 >/dev/null)"; then
      echo "$out" >&2
      exit 2
    fi
  '';
in
{
  # Before the TCC grants (mkBefore, modules/darwin/tcc.nix) and home-manager.
  system.activationScripts.postActivation.text = lib.mkOrder 400 ''
    # ================================================================
    # Unlock the deus-signing keychain (hosts/mini/signing-keychain.nix)
    # ================================================================
    if [ ! -s ${passFile} ]; then
      echo "warning: ${passFile} is missing; the signing keychain stays locked (codesign falls back)" >&2
    elif ! launchctl asuser "$(id -u -- ${user})" sudo -u ${user} ${unlock}; then
      echo "warning: could not unlock ${keychain}; codesign falls back" >&2
    fi
  '';
}
