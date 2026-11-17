# construct Android release: build the app (the Expo app in app/mobile, io.matv.construct), sign it with the app key
# and publish it to the private F-Droid repo that construct serves at /fdroid/repo. Builds need an x86_64 host (the
# SDK's aapt2 and zipalign are x86-64 only), so when construct runs on another machine the release copies repo/ there;
# the fdroid working dir (config, repo signing key) stays here.
#
#   git -C <srcDir> pull --ff-only && construct-android-release
#
# The build and the repo update live in the construct repo (app/mobile/scripts/fdroid-release.sh); this adds the key,
# a lock and the copy to raven. The Expo app replaced the Kotlin app in place in November 2026 (same package and key,
# a higher versionCode); the side-by-side build "construct RN" (io.matv.construct.rn, construct-rn-release) is retired
# and the release drops its APKs from the repo.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.constructAndroidRelease;
in
{
  options.programs.constructAndroidRelease = {
    enable = lib.mkEnableOption "the construct-android-release command";

    srcDir = lib.mkOption {
      type = lib.types.str;
      example = "/home/matv/construct-android/src";
      description = "A checkout of the construct repo; the release builds its app/mobile as checked out (pull it first).";
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

    signerSha256 = lib.mkOption {
      type = lib.types.str;
      # The app certificate (sops android_keystore_b64, alias "construct"), as F-Droid's index lists it.
      default = "f6128da57407424eba60ebca9b1d41fa74e0be198314b03bbd199f93430e38df";
      description = "SHA-256 of the app signing certificate; an APK signed otherwise is refused (it could not update the app).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "construct-android-release" ''
        set -euo pipefail
        set +o xtrace
        mkdir -p ${cfg.fdroidDir}
        exec 9>>${cfg.fdroidDir}/.release.lock
        ${pkgs.util-linux}/bin/flock -n 9 || { echo "another F-Droid release is running (lock ${cfg.fdroidDir}/.release.lock)" >&2; exit 1; }
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        (umask 077; base64 -d ${config.sops.secrets.android_keystore_b64.path} > "$tmp/construct.p12")
        cd ${cfg.srcDir}
        # The APK also stays in ~/construct-android/apk for Taildrop.
        FDROID_DIR=${cfg.fdroidDir} \
        OUT_DIR=$HOME/construct-android/apk \
        KEYSTORE_FILE="$tmp/construct.p12" \
        KEYSTORE_PASSWORD_FILE=${config.sops.secrets.android_keystore_password.path} \
        KEY_PASSWORD_FILE=${config.sops.secrets.android_keystore_password.path} \
        KEY_ALIAS=construct \
        EXPECT_SIGNER_SHA256=${cfg.signerSha256} \
          nix develop ./app/mobile#android -c bash app/mobile/scripts/fdroid-release.sh
        ${lib.optionalString (cfg.publishTo != null) ''
          echo "→ publish repo/ to ${cfg.publishTo}"
          ${pkgs.rsync}/bin/rsync -a --delete ${cfg.fdroidDir}/repo/ ${cfg.publishTo}
        ''}
      '')
      # Retired with the cutover; kept a while so the old command says where it went.
      (pkgs.writeShellScriptBin "construct-rn-release" ''
        echo "construct-rn-release is retired: construct-android-release builds the Expo app as io.matv.construct" >&2
        echo "  git -C ${cfg.srcDir} pull --ff-only && construct-android-release" >&2
        exit 1
      '')
    ];
  };
}
