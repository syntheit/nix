# Automated deus CLI release (see docs/runbooks/cli-release.md in malli-deus).
#
# A launchd user agent (daniel's login session: the release key and the notary
# profile live in daniel's Keychains) polls GitHub every 5 minutes for a new
# cli-vX.Y.Z tag and, after the gates in deus-cli-release.sh, builds, Apple-signs,
# signs the manifest and rsyncs to vista's restricted deus-release account.
#
# SECURITY BOUNDARY: the pipeline script, the Apple signing script and the
# manifest signer are pinned HERE, built from this flake's locked inputs.deus,
# not from the release tag. Tag code only runs inside `nix build`.
#
# One-time setup on mini: see "Automated (mini)" in malli-deus
# docs/runbooks/cli-release.md.
{
  pkgs,
  lib,
  vars,
  inputs,
  ...
}:

let
  # --- config ---------------------------------------------------------------
  home = "/Users/${vars.user.name}";
  repoUrl = "git@github-malli-deus:NRE-Product/malli-deus.git"; # ssh alias in home/modules/ssh.nix
  # How mini reaches vista: vista's own tailscale is on the personal tailnet,
  # which mini is on (MagicDNS name). Override here if that changes.
  publishHost = "vista";
  publishUser = "deus-release";
  sshKey = "${home}/.ssh/deus-release_ed25519";
  keychainService = "deus-cli-release";
  keychainAccount = "release-key";
  stateDir = "${home}/Library/Application Support/deus-cli-release";
  logFile = "${home}/Library/Logs/deus-cli-release.log";
  intervalSeconds = 300;

  # --- pinned signer: cmd/deus-release from the locked deus input -------------
  # Same source and vendor hash as the deus flake's own Go packages, so no hash
  # of ours to keep in sync.
  common = import "${inputs.deus}/nix/go-common.nix" { inherit lib; };
  deus-release = pkgs.buildGoModule {
    pname = "deus-release";
    inherit (common) version src vendorHash;
    subPackages = [ "cmd/deus-release" ];
    env.CGO_ENABLED = "0";
    env.GOFLAGS = "-trimpath -buildvcs=false";
    ldflags = [ "-s" "-w" ];
    doCheck = false;
    meta.mainProgram = "deus-release";
  };

  # Pinned copy of ~/malli-plans/signing/sign-and-notarize.sh (uses the
  # deus-signing keychain and deus-notary profile set up by
  # setup-signing-on-mini.sh).
  signAndNotarize = pkgs.writeShellApplication {
    name = "deus-cli-sign-and-notarize";
    runtimeInputs = [ pkgs.coreutils ];
    excludeShellChecks = [ "SC2016" ];
    text = ''
      export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin"
      ${builtins.readFile ./deus-cli-sign-and-notarize.sh}
    '';
  };

  pipeline = pkgs.writeShellApplication {
    name = "deus-cli-release";
    runtimeInputs = [
      pkgs.git
      pkgs.rsync
      pkgs.openssh
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.jq
      deus-release
      signAndNotarize
    ];
    text = ''
      export DCR_REPO_URL=${lib.escapeShellArg repoUrl}
      export DCR_STATE_DIR=${lib.escapeShellArg stateDir}
      export DCR_LOG=${lib.escapeShellArg logFile}
      export DCR_PUBLISH_HOST=${lib.escapeShellArg publishHost}
      export DCR_PUBLISH_USER=${lib.escapeShellArg publishUser}
      export DCR_SSH_KEY=${lib.escapeShellArg sshKey}
      export DCR_KEYCHAIN_SERVICE=${lib.escapeShellArg keychainService}
      export DCR_KEYCHAIN_ACCOUNT=${lib.escapeShellArg keychainAccount}
      export DCR_RELEASE_BIN=${deus-release}/bin/deus-release
      export DCR_SIGN_BIN=${signAndNotarize}/bin/deus-cli-sign-and-notarize
      ${builtins.readFile ./deus-cli-release.sh}
    '';
  };
in
{
  environment.systemPackages = [ pipeline ];

  launchd.user.agents.deus-cli-release = {
    serviceConfig = {
      ProgramArguments = [ "${pipeline}/bin/deus-cli-release" ];
      StartInterval = intervalSeconds;
      RunAtLoad = false;
      ProcessType = "Background";
      StandardOutPath = "${home}/Library/Logs/deus-cli-release.launchd.log";
      StandardErrorPath = "${home}/Library/Logs/deus-cli-release.launchd.log";
    };
  };
}
