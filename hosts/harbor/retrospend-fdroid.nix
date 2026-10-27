{ config, pkgs, ... }:

# Private F-Droid repo "Retrospend dev": signed Android builds of the Retrospend
# app, installed and updated from Droid-ify or F-Droid by URL, no cable.
# Same pattern as construct's repo (modules/construct-life.nix), but nginx serves
# it because dev.retrospend.app points at the Next.js container, not at a file tree.
#
#   retrospend-fdroid-release     build, sign and publish the current checkout
#
# nginx listens on 127.0.0.1:1999 and the harbor tunnel exposes it at
# https://fdroid.retrospend.app (ingress in access.nix). One-time DNS CNAME:
#   cloudflared tunnel route dns harbor fdroid.retrospend.app
# Basic auth: user "daniel", password retrospend_fdroid_password (sops).
# Only /repo is served; the repo key and config in the same directory are not.

let
  dir = "/var/lib/retrospend-fdroid";
  srcDir = "/home/matv/Projects/retrospend";
  htpasswd = config.sops.templates."retrospend-fdroid-htpasswd".path;
in
{
  # nginx reads {PLAIN} entries, so the plain password in sops stays the only copy.
  sops.templates."retrospend-fdroid-htpasswd" = {
    content = "daniel:{PLAIN}${config.sops.placeholder.retrospend_fdroid_password}\n";
    owner = config.services.nginx.user;
    mode = "0400";
  };

  # The release script runs as matv and writes here; nginx only reads.
  systemd.tmpfiles.rules = [ "d ${dir} 0755 matv users -" ];

  services.nginx = {
    enable = true;
    virtualHosts."retrospend-fdroid" = {
      listen = [ { addr = "127.0.0.1"; port = 1999; } ];
      root = dir;
      extraConfig = ''
        auth_basic "Retrospend dev";
        auth_basic_user_file ${htpasswd};
      '';
      locations."/repo/".extraConfig = ''
        # The index changes on each release; phones must not keep an old copy.
        add_header Cache-Control "no-cache";
      '';
      locations."/".return = "404";
    };
  };

  environment.systemPackages = [
    # Build, sign and publish the Android app to the private F-Droid repo.
    # RETROSPEND_SRC picks another checkout (default: the main one).
    (pkgs.writeShellScriptBin "retrospend-fdroid-release" ''
      set -euo pipefail
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      base64 -d ${config.sops.secrets.retrospend_android_keystore_b64.path} > "$tmp/retrospend.p12"
      cd "''${RETROSPEND_SRC:-${srcDir}}"
      export FDROID_DIR=${dir} KEY_ALIAS=retrospend
      export KEYSTORE_FILE="$tmp/retrospend.p12"
      export KEYSTORE_PASSWORD_FILE=${config.sops.secrets.retrospend_android_keystore_password.path}
      export KEY_PASSWORD_FILE=${config.sops.secrets.retrospend_android_keystore_password.path}
      # Heavy build: one at a time on harbor, like every other heavy command.
      # No exec: the trap removes the decoded keystore afterwards.
      ${pkgs.util-linux}/bin/flock /tmp/retrospend-heavy.lock \
        nix develop .#android -c bash -c '
          pnpm install --frozen-lockfile --ignore-scripts --filter "@retrospend/mobile..."
          bash apps/mobile/scripts/android-release.sh'
    '')
  ];
}
