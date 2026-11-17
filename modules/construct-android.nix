# construct Android release: build, sign and publish the app to the private F-Droid repo that construct serves at
# /fdroid/repo. Builds need an x86_64 host (the SDK's aapt2 and zipalign are x86-64 only), so when construct runs on
# another machine the release copies repo/ there; the fdroid working dir (config, repo signing key) stays here.
#
# Two apps share the one repo: the Kotlin app (io.matv.construct, construct-android-release) and, until the Expo
# cutover, "construct RN" (io.matv.construct.rn, construct-rn-release). Each adds its APK to fdroidDir/repo and runs
# `fdroid update` over all of them; a lock keeps two releases from interleaving.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.constructAndroidRelease;
  lock = ''
    mkdir -p ${cfg.fdroidDir}
    exec 9>>${cfg.fdroidDir}/.release.lock
    ${pkgs.util-linux}/bin/flock -n 9 || { echo "another F-Droid release is running (lock ${cfg.fdroidDir}/.release.lock)" >&2; exit 1; }
  '';
  publish = lib.optionalString (cfg.publishTo != null) ''
    echo "→ publish repo/ to ${cfg.publishTo}"
    ${pkgs.rsync}/bin/rsync -a --delete ${cfg.fdroidDir}/repo/ ${cfg.publishTo}
  '';
in
{
  options.programs.constructAndroidRelease = {
    enable = lib.mkEnableOption "the construct-android-release command";

    androidDir = lib.mkOption {
      type = lib.types.str;
      description = "The android/ project in the construct repo (its dev shell also runs fdroid for construct RN).";
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

    rn = {
      enable = lib.mkEnableOption "the construct-rn-release command (the Expo app, io.matv.construct.rn)";

      srcDir = lib.mkOption {
        type = lib.types.str;
        example = "/home/matv/construct-rn/src";
        description = "A checkout of the construct repo; the release builds its app/mobile as checked out (pull it first).";
      };

      signingDir = lib.mkOption {
        type = lib.types.str;
        example = "/home/matv/construct-rn/signing";
        description = "Holds construct-rn.p12 and password (app/mobile/scripts/android-keystore.sh); outside the checkout.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "construct-android-release" ''
        set -euo pipefail
        ${lock}
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        base64 -d ${config.sops.secrets.android_keystore_b64.path} > "$tmp/construct.p12"
        cd ${cfg.androidDir}
        export FDROID_DIR=${cfg.fdroidDir} KEY_ALIAS=construct
        export KEYSTORE_FILE="$tmp/construct.p12"
        export KEYSTORE_PASSWORD_FILE=${config.sops.secrets.android_keystore_password.path}
        export KEY_PASSWORD_FILE=${config.sops.secrets.android_keystore_password.path}
        nix develop -c scripts/release.sh
        ${publish}
      '')
    ]
    ++ lib.optional cfg.rn.enable (
      pkgs.writeShellScriptBin "construct-rn-release" ''
        # Builds construct RN from ${cfg.rn.srcDir} (app/mobile/scripts/android-release.sh, signed with the RN key in
        # ${cfg.rn.signingDir}), adds the APK to the F-Droid repo beside the Kotlin app and publishes the repo.
        # The APK also stays in ~/construct-rn/apk (the script's default OUT_DIR) for Taildrop.
        set -euo pipefail
        set +o xtrace
        ${lock}
        src=${cfg.rn.srcDir}
        fdroid=${cfg.fdroidDir}
        [ -f "$fdroid/config.yml" ] || { echo "no F-Droid repo in $fdroid: run construct-android-release once first" >&2; exit 1; }
        n=$(git -C "$src" rev-list --count HEAD)
        app_id=io.matv.construct.rn
        if [ -f "$fdroid/repo/''${app_id}_$n.apk" ]; then
          echo "build $n ($app_id) is already in the repo: pull or commit in $src first" >&2
          exit 1
        fi
        echo "→ build $app_id $n from $src ($(git -C "$src" log -1 --format='%h %s'))"
        [ -z "$(git -C "$src" status --porcelain)" ] || echo "warning: $src has uncommitted changes; they ship in build $n" >&2
        out=$HOME/construct-rn/apk
        cd "$src"
        KEYSTORE_FILE=${cfg.rn.signingDir}/construct-rn.p12 \
        KEYSTORE_PASSWORD_FILE=${cfg.rn.signingDir}/password \
        KEY_PASSWORD_FILE=${cfg.rn.signingDir}/password \
        KEY_ALIAS=construct-rn \
        CONSTRUCT_APP_VARIANT=rn \
        CONSTRUCT_BUILD_NUMBER=$n \
        OUT_DIR=$out \
          nix develop ./app/mobile#android -c bash app/mobile/scripts/android-release.sh

        umask 022 # the served repo stays readable by construct
        install -m 644 "$out/''${app_id}_$n.apk" "$fdroid/repo/''${app_id}_$n.apk"
        if [ ! -f "$fdroid/metadata/$app_id.yml" ]; then
          cat > "$fdroid/metadata/$app_id.yml" <<'YML'
        Categories:
          - Internet
        License: Unknown
        Name: construct RN
        Summary: The Expo build of construct, beside the Kotlin app
        Description: |-
          The React Native (Expo) client of construct, installed beside the Kotlin app until it replaces it.
        YML
        fi
        # fdroid (and the SDK tools it calls) from the Kotlin app's dev shell, as construct-android-release runs it.
        (cd ${cfg.androidDir} && nix develop -c sh -c 'cd "$1" && fdroid update' sh "$fdroid")
        echo "published $app_id build $n"
        ${publish}
      ''
    );
  };
}
