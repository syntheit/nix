# construct Android release: build, sign and publish the app to the private F-Droid repo that construct serves at
# /fdroid/repo. Builds need an x86_64 host (the SDK's aapt2 and zipalign are x86-64 only), so when construct runs on
# another machine the release copies repo/ there; the fdroid working dir (config, repo signing key) stays here.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.constructAndroidRelease;
in
{
  options.programs.constructAndroidRelease = {
    enable = lib.mkEnableOption "the construct-android-release command";

    androidDir = lib.mkOption {
      type = lib.types.str;
      description = "The android/ project in the construct repo.";
    };

    fdroidDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/construct/fdroid";
      description = "fdroid working dir: config, repo signing key, metadata and the published repo/.";
    };

    publishTo = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "raven:/var/lib/construct/fdroid/repo/";
      description = "rsync target for repo/ when construct runs on another host; null when construct serves fdroidDir here.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "construct-android-release" ''
        set -euo pipefail
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        base64 -d ${config.sops.secrets.android_keystore_b64.path} > "$tmp/construct.p12"
        cd ${cfg.androidDir}
        export FDROID_DIR=${cfg.fdroidDir} KEY_ALIAS=construct
        export KEYSTORE_FILE="$tmp/construct.p12"
        export KEYSTORE_PASSWORD_FILE=${config.sops.secrets.android_keystore_password.path}
        export KEY_PASSWORD_FILE=${config.sops.secrets.android_keystore_password.path}
        nix develop -c scripts/release.sh
        ${lib.optionalString (cfg.publishTo != null) ''
          echo "→ publish repo/ to ${cfg.publishTo}"
          ${pkgs.rsync}/bin/rsync -a --delete ${cfg.fdroidDir}/repo/ ${cfg.publishTo}
        ''}
      '')
    ];
  };
}
