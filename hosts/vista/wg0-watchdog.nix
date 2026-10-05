{ pkgs, ... }:
{
  # Rebind wg0's UDP socket when the conduit handshake is stale. WireGuard never
  # changes its own source port, so a stale NAT mapping on the home router is
  # refreshed forever by the 25 s keepalives; a new port gets a fresh mapping.
  systemd.services.wg0-watchdog = {
    description = "Rebind wg0 when the conduit handshake goes stale";
    after = [ "wg-quick-wg0.service" ];
    path = with pkgs; [ wireguard-tools coreutils gawk iputils systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      peer=bhXOmLJsZDR0ZeF/Wnzt116Jw0tHzbfhoe2kG2+ZDAw=   # conduit (public key)
      now=$(date +%s)
      systemctl is-active --quiet wg-quick-wg0.service || exit 0
      ping -c1 -W3 192.3.203.146 >/dev/null 2>&1 || exit 0   # WAN down: nothing to fix yet
      hs=$(wg show wg0 latest-handshakes | awk -v p="$peer" '$1==p{print $2}')
      up=$(date -d "$(systemctl show -p ActiveEnterTimestamp --value wg-quick-wg0.service)" +%s)
      [ "''${hs:-0}" -lt "$up" ] && hs=$up       # never handshaken: count from unit start
      age=$(( now - hs ))
      [ "$age" -gt 180 ] || exit 0
      stamp=/run/wg0-watchdog.restart
      if [ "$age" -gt 600 ] && { [ ! -e "$stamp" ] || [ $(( now - $(stat -c %Y "$stamp") )) -gt 900 ]; }; then
        touch "$stamp"
        echo "wg0 handshake $age s old, rebind did not help: restarting wg-quick-wg0"
        systemctl restart wg-quick-wg0.service
        exit 0
      fi
      echo "wg0 handshake $age s old: rebinding UDP socket (new NAT mapping)"
      wg set wg0 listen-port 0
    '';
  };
  systemd.timers.wg0-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "5min"; OnUnitActiveSec = "60s"; AccuracySec = "10s"; };
  };
}
