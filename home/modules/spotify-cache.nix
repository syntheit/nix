{
  config,
  lib,
  pkgs,
  ...
}:

# Spotify's streaming cache (~/.cache/spotify/Data, 10 GB on mantle) lives in
# /tmp, which is tmpfs on mantle: every streamed track used to be written to
# the SSD (~1.3 GB/h while playing). Capped at 1 GB and refilled from the
# network after a reboot. Offline downloads (~/.cache/spotify/Storage) stay on
# disk.
let
  cache = "/tmp/spotify-cache-${config.home.username}";
  pgrep = "${pkgs.procps}/bin/pgrep";
in
{
  systemd.user.tmpfiles.rules = [ "d ${cache} 0700 - - -" ];

  # Only while Spotify isn't running: it holds the cache open, and it rewrites
  # its prefs file on exit. At boot it never is, so this lands then at the latest.
  home.activation.spotifyCacheInRam = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! ${pgrep} -f '\.spotify-wrapped' >/dev/null; then
      data="$HOME/.cache/spotify/Data"
      if [ ! -L "$data" ]; then
        mkdir -p "${cache}" "$HOME/.cache/spotify"
        rm -rf "$data"
        ln -s "${cache}" "$data"
      fi
      prefs="$HOME/.config/spotify/prefs"
      if [ -f "$prefs" ]; then
        ${pkgs.gnused}/bin/sed -i '/^storage\.size=/d' "$prefs"
        echo 'storage.size=1024' >> "$prefs"
      fi
    fi
  '';
}
