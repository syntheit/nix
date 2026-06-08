{ config, pkgs, ... }:

# =====================================================================
# torrent-cleaner — nightly purge of zero-seed / metadata-stuck torrents
# from qBittorrent, going through Sonarr/Radarr so they blocklist the
# release hash and re-search for a different one.
#
# Without this, *arr grabs aggressively from low-seed indexers and
# qBit accumulates hundreds of torrents that will never complete,
# eventually saturating its queue.
# =====================================================================

let
  staleHours = 24;
in
{
  systemd.services.torrent-cleaner = {
    description = "Purge stale stalled/metaDL torrents (>${toString staleHours}h, no peers) via *arr";
    after = [
      "docker.service"
      "docker-qbittorrent.service"
      "docker-sonarr.service"
      "docker-radarr.service"
    ];
    wants = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root"; # needs to read *arr config.xml + /run/secrets
      ExecStart = pkgs.writeShellScript "torrent-cleaner" ''
        set -euo pipefail

        SONARR_API=$(${pkgs.gnugrep}/bin/grep -oP '(?<=<ApiKey>)[^<]+' /arespool/appdata/sonarr/config.xml)
        RADARR_API=$(${pkgs.gnugrep}/bin/grep -oP '(?<=<ApiKey>)[^<]+' /arespool/appdata/radarr/config.xml)
        QBIT_PW=$(${pkgs.coreutils}/bin/cat /run/secrets/qbittorrent_webui_password)

        if [ ''${#SONARR_API} -ne 32 ] || [ ''${#RADARR_API} -ne 32 ]; then
          echo "ERROR: API key length mismatch (sonarr=''${#SONARR_API}, radarr=''${#RADARR_API})" >&2
          exit 1
        fi

        # qBit 4.x sets `SID=...`; qBit 5.x switched to `QBT_SID_<port>=...`.
        # Capture name=value so we can pass it to Cookie: as-is rather than
        # hard-coding the old `SID` name (which silently broke the cleaner
        # after the 5.2 upgrade).
        COOKIE=$(${pkgs.curl}/bin/curl -s -i -X POST 'http://127.0.0.1:9091/api/v2/auth/login' \
          --data-urlencode "username=admin" --data-urlencode "password=$QBIT_PW" \
          -H 'Referer: http://127.0.0.1:9091' \
          | ${pkgs.gnugrep}/bin/grep -oiP '(?<=^set-cookie: )(QBT_SID_[0-9]+|SID)=[^;]+' | head -1)
        if [ -z "$COOKIE" ]; then
          echo "ERROR: qBittorrent auth failed" >&2
          exit 1
        fi

        ${pkgs.python3}/bin/python3 - "$COOKIE" "$SONARR_API" "$RADARR_API" <<'PY'
import json, sys, urllib.request, urllib.parse, time, collections

COOKIE, SONARR_KEY, RADARR_KEY = sys.argv[1], sys.argv[2], sys.argv[3]
STALE_HOURS = ${toString staleHours}
NOW = time.time()

def qbit(path, method='GET', data=None):
    headers = {'Cookie': COOKIE}
    if data is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
        data = urllib.parse.urlencode(data).encode()
    r = urllib.request.Request(f'http://127.0.0.1:9091{path}', headers=headers,
                               method=method, data=data)
    return urllib.request.urlopen(r, timeout=20).read()

def qbit_json(path):
    return json.loads(qbit(path))

def arr_get(base, key, path):
    r = urllib.request.Request(f'{base}{path}', headers={'X-Api-Key': key, 'Accept':'application/json'})
    return json.loads(urllib.request.urlopen(r, timeout=20).read())

def arr_delete(base, key, qid):
    url = f'{base}/api/v3/queue/{qid}?removeFromClient=true&blocklist=true&skipRedownload=false'
    r = urllib.request.Request(url, method='DELETE', headers={'X-Api-Key': key})
    urllib.request.urlopen(r, timeout=20).read()

def queue_map(base, key):
    out = {}
    page = 1
    while True:
        r = arr_get(base, key, f'/api/v3/queue?page={page}&pageSize=1000&includeUnknownItems=true')
        for item in r.get('records', []):
            h = (item.get("downloadId") or "").lower()
            if h: out[h] = item['id']
        if not r.get('records') or len(r['records']) < 1000: return out
        page += 1
        if page > 50: return out

torrents = qbit_json('/api/v2/torrents/info')
stale = [t for t in torrents
         if t['state'] in ('stalledDL', 'metaDL')
         and (NOW - t['added_on']) > STALE_HOURS*3600]

print(f"torrent-cleaner: {len(torrents)} torrents in qBit, {len(stale)} stale >{STALE_HOURS}h")
if not stale:
    sys.exit(0)

by_cat = collections.Counter(t.get('category','(none)') for t in stale)
for c, n in by_cat.most_common():
    print(f"  candidates: {n:4d}  {c}")

sm = queue_map('http://127.0.0.1:8989', SONARR_KEY)
rm = queue_map('http://127.0.0.1:7878', RADARR_KEY)

stats = {'radarr': 0, 'sonarr': 0, 'orphan': 0, 'errors': 0}
for t in stale:
    h = t['hash'].lower()
    cat = t.get("category", "")
    try:
        if cat.startswith('radarr') and h in rm:
            arr_delete('http://127.0.0.1:7878', RADARR_KEY, rm[h]); stats['radarr'] += 1
        elif cat.startswith('tv-sonarr') and h in sm:
            arr_delete('http://127.0.0.1:8989', SONARR_KEY, sm[h]); stats['sonarr'] += 1
        else:
            qbit('/api/v2/torrents/delete', 'POST', {'hashes': h, 'deleteFiles': 'true'})
            stats['orphan'] += 1
    except Exception as e:
        stats['errors'] += 1
        print(f"  fail {h[:8]}: {e}", file=sys.stderr)

print(f"torrent-cleaner: removed via radarr={stats['radarr']} sonarr={stats['sonarr']} "
      f"orphan_qbit={stats['orphan']} errors={stats['errors']}")
PY
      '';
    };
  };

  systemd.timers.torrent-cleaner = {
    description = "Run torrent-cleaner nightly to purge dead torrents";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:45:00"; # after recyclarr (04:30), before backups
      RandomizedDelaySec = "15min";
      Persistent = true;
    };
  };
}
